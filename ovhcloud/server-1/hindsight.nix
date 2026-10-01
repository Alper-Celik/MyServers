# The hindsight container and the host user it runs as.
#
# It runs with the UID of the host user `hindsight` (984, free fleet-wide), so
# pg_hba's default `local all all peer` matches the postgres role of the same
# name (postgres.nix) — socket access with no password and no hba change.
{
  config,
  hindsightPorts,
  postgresSocketDir,
  lib,
  ...
}:
let
  hindsight-uid = 984;
  hindsight-gid = 984;
  port-api = 21912;
  port = 21911;
  hindsight = config.virtualisation.oci-containers.containers.hindsight;
in
{
  users = {
    groups.hindsight.gid = hindsight-gid;
    users.hindsight = {
      isSystemUser = true;
      group = "hindsight";
      uid = hindsight-uid;
      home = "/var/lib/hindsight";
    };
  };

  # Alper adds HINDSIGHT_OPENROUTER_API_KEY to secrets/ovhcloud/server-1.yaml.
  # Service-scoped on purpose: each service keeps its own OpenRouter key/quota
  # (hetzner's hermes uses the unprefixed OPENROUTER_API_KEY).
  sops.secrets.HINDSIGHT_OPENROUTER_API_KEY = { };

  # hindsight reads its own variable names, so one key feeds every one of them;
  # the Jev failover member (container.nix) inherits no shared key, so its own
  # variable is spelled out too
  sops.templates."hindsight-env" = {
    content = ''
      HINDSIGHT_API_OPENROUTER_API_KEY=${config.sops.placeholder.HINDSIGHT_OPENROUTER_API_KEY}
      HINDSIGHT_API_LLM_API_KEY=${config.sops.placeholder.HINDSIGHT_OPENROUTER_API_KEY}
      HINDSIGHT_API_RERANKER_1_TYPESAFE_API_KEY=${config.sops.placeholder.HINDSIGHT_OPENROUTER_API_KEY}
    '';
    restartUnits = [
      "${config.virtualisation.oci-containers.containers.hindsight.serviceName}.service"
    ];
  };

  virtualisation.oci-containers.containers.hindsight = {
    image = "ghcr.io/vectorize-io/hindsight:latest-slim";
    environment = {
      # `?host=<dir>` = unix socket (see common/postgres-sockets.nix)
      HINDSIGHT_API_DATABASE_URL = "postgresql://hindsight@/hindsight?host=${postgresSocketDir}";
      HINDSIGHT_API_VECTOR_EXTENSION = "vchord";
      HINDSIGHT_API_LLM_PROVIDER = "openrouter";
      # open weights, MIT (HF deepseek-ai/DeepSeek-V4.1-Flash); unset → qwen/qwen3.5-9b
      HINDSIGHT_API_LLM_MODEL = "deepseek/deepseek-v4.1-flash";
      # This slug is a thinking model: OpenRouter's metadata carries
      # reasoning.default_enabled=true / default_effort=high, and the trace rows
      # show thoughts as the bulk of what it generates. Pin the effort per lane —
      # retain (fact extraction) and consolidation are structured, mechanical
      # passes; reflect keeps the default because that lane synthesizes answers.
      # The slug accepts max|high|low only (no minimal/medium/none), and
      # Hindsight passes the value through as `reasoning_effort` because its
      # DeepSeek name heuristic only flags v4-pro/reasoner/r1/thinking.
      HINDSIGHT_API_RETAIN_LLM_REASONING_EFFORT = "low";
      HINDSIGHT_API_CONSOLIDATION_LLM_REASONING_EFFORT = "low";
      # Output budget per call. Unset means the provider's implicit cap (131072
      # for this slug), and OpenRouter reserves max_tokens x completion price
      # against the balance for every in-flight call — a burst of consolidation
      # calls each reserving ~$0.065 is what turns a thin balance into HTTP 402
      # ("you requested up to 131072 tokens, but can only afford 15301").
      # 16384 is ~1.5x the largest call seen on the live bank (11.3k
      # output+thinking) and stays above RETAIN_CHUNK_SIZE (3000).
      HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS = "16384";
      HINDSIGHT_API_CONSOLIDATION_MAX_COMPLETION_TOKENS = "16384";
      HINDSIGHT_API_EMBEDDINGS_PROVIDER = "openrouter";
      # open weights, Apache-2.0 (HF Qwen/Qwen3-Embedding-8B); unset → perplexity/pplx-embed-v1-0.6b
      HINDSIGHT_API_EMBEDDINGS_OPENROUTER_MODEL = "qwen/qwen3-embedding-8b";
      # open weights, Apache-2.0 (HF Qwen/Qwen3-Reranker-8B); unset → cohere/rerank-v3.5
      HINDSIGHT_API_RERANKER_PROVIDER = "openrouter";
      HINDSIGHT_API_RERANKER_OPENROUTER_MODEL = "qwen/qwen3-reranker-8b";
      # failover 1: Jev (TypeSafe decision model) via OpenRouter's System One API —
      # member 1 inherits nothing, so model/base URL/key are all spelled out
      HINDSIGHT_API_RERANKER_1_PROVIDER = "typesafe";
      HINDSIGHT_API_RERANKER_1_TYPESAFE_MODEL = "typesafe/jev-1.13";
      HINDSIGHT_API_RERANKER_1_TYPESAFE_BASE_URL = "https://openrouter.ai/api";
      # failover 2: no model — keep the RRF order rather than fail recall
      HINDSIGHT_API_RERANKER_2_PROVIDER = "rrf";
    };
    environmentFiles = [ config.sops.templates."hindsight-env".path ];
    user = "${toString hindsight-uid}:${toString hindsight-gid}";
    volumes = [ "${postgresSocketDir}:${postgresSocketDir}" ];
    ports = [
      "${toString port-api}:8888"
      "${toString port}:9999"
    ];
    labels = {
      "io.containers.autoupdate" = "registry";
    };
    autoStart = true;
  };

  services.postgresql = {
    extensions = ps: [
      ps.pgvector
      ps.vectorchord
    ];
    ensureDatabases = [ "hindsight" ];
    settings = {
      shared_preload_libraries = [ "vchord.so" ];
    };
    ensureUsers = [
      {
        name = "hindsight";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
  };

  # enable the extension inside the hindsight DB (idempotent; immich-module pattern)
  systemd.services.postgresql-setup.serviceConfig.ExecStartPost = [
    ''${lib.getExe' config.services.postgresql.package "psql"} -d hindsight -c "CREATE EXTENSION IF NOT EXISTS vector;ALTER EXTENSION vector UPDATE;"''
    ''${lib.getExe' config.services.postgresql.package "psql"} -d hindsight -c "CREATE EXTENSION IF NOT EXISTS vchord;ALTER EXTENSION vchord UPDATE;"''
  ];

  # the socket has to exist before the first connect; hindsight retries, but an
  # ordered start avoids a noisy boot
  systemd.services.${hindsight.serviceName}.after = [ "postgresql.service" ];

  services.caddy.virtualHosts."hindsight.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://localhost:${toString port}";
  };

  services.caddy.virtualHosts."api.hindsight.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://localhost:${toString port-api}";
  };
}
