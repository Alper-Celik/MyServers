# The hindsight container and the host user it runs as.
#
# It runs with the UID of the host user `hindsight` (984, free fleet-wide), so
# pg_hba's default `local all all peer` matches the postgres role of the same
# name (postgres.nix) — socket access with no password and no hba change.
{
  config,
  inputs,
  pkgs,
  postgresSocketDir,
  lib,
  ...
}:
let
  secrets = inputs.MyServersSecrets;
  hindsight-uid = 984;
  hindsight-gid = 984;
  port-api = 21912;
  port = 21911;
  hindsight = config.virtualisation.oci-containers.containers.hindsight;
  sopsFile = "${secrets}/secrets/ovhcloud/server-1.yaml";
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

  # Secrets resolve through SecretSpec (common/secretspec.nix) instead of a
  # sops template. The manifest is plaintext — key names only, same names the
  # sops route already exposed in this file — and resolves HINDSIGHT_OPENROUTER_API_KEY
  # (Alper adds it to secrets/ovhcloud/server-1.yaml; service-scoped on
  # purpose: each service keeps its own OpenRouter key/quota) into the three
  # variable names hindsight reads.
  secretspec.render.hindsight = {
    manifest = ''
      [project]
      name = "hindsight"
      revision = "1.0"

      [providers]
      enc = "sops://${sopsFile}"

      [profiles.default]
      HINDSIGHT_API_OPENROUTER_API_KEY = { description = "OpenRouter key", ref = { item = "HINDSIGHT_OPENROUTER_API_KEY" }, providers = ["enc"] }
      HINDSIGHT_API_LLM_API_KEY = { ref = { item = "HINDSIGHT_OPENROUTER_API_KEY" }, providers = ["enc"] }
      HINDSIGHT_API_RERANKER_1_TYPESAFE_API_KEY = { ref = { item = "HINDSIGHT_OPENROUTER_API_KEY" }, providers = ["enc"] }
    '';
    sopsFile = sopsFile;
    provider = "enc";
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
      HINDSIGHT_API_RETAIN_LLM_MODEL = "@preset/hindsight-retain";
      HINDSIGHT_API_CONSOLIDATION_LLM_MODEL = "@preset/hindsight-consolidation";
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
    environmentFiles = [ config.secretspec.render.hindsight.path ];
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
  systemd.services.${hindsight.serviceName} = {
    after = [
      "postgresql.service"
      config.secretspec.render.hindsight.service
    ];
    requires = [ config.secretspec.render.hindsight.service ];
    # a new secrets generation changes the sopsFile store path, so this
    # restarts the container with the freshly rendered env file
    restartTriggers = [ sopsFile ];
  };

  services.caddy.virtualHosts."hindsight.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://localhost:${toString port}";
  };

  services.caddy.virtualHosts."api.hindsight.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://localhost:${toString port-api}";
  };
}
