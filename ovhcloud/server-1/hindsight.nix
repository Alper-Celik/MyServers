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
  port = 21912;
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
      HINDSIGHT_API_LLM_PROVIDER = "openrouter";
      # open weights, MIT (HF deepseek-ai/DeepSeek-V4.1-Flash); unset → qwen/qwen3.5-9b
      HINDSIGHT_API_LLM_MODEL = "deepseek/deepseek-v4.1-flash";
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
      HINDSIGHT_API_PORT = toString port;
    };
    environmentFiles = [ config.sops.templates."hindsight-env".path ];
    user = "${toString hindsight-uid}:${toString hindsight-gid}";
    volumes = [ "${postgresSocketDir}:${postgresSocketDir}" ];
    ports = [
      "${toString port}:${toString port}"
    ];
    labels = {
      "io.containers.autoupdate" = "registry";
    };
    autoStart = true;
  };

  services.postgresql = {
    # pgvector — hindsight's `vector` extension. Immich's pgvecto-rs
    # (vectors.so) is related but NOT the same; do not copy its setup.
    # Note: changes the effective postgres package → postgres restarts on deploy.
    extensions = ps: [ ps.pgvector ];
    ensureDatabases = [ "hindsight" ];
    ensureUsers = [
      {
        name = "hindsight";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
  };

  # enable the extension inside the hindsight DB (idempotent; immich-module pattern)
  systemd.services.postgresql.serviceConfig.ExecStartPost = [
    ''${lib.getExe' config.services.postgresql.package "psql"} -d hindsight -c "CREATE EXTENSION IF NOT EXISTS vector"''
  ];

  # the socket has to exist before the first connect; hindsight retries, but an
  # ordered start avoids a noisy boot
  systemd.services.${hindsight.serviceName}.after = [ "postgresql.service" ];

  services.caddy.virtualHosts."hindsight.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://localhost:${toString port}";
  };
}
