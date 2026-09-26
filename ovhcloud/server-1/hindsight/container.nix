# The hindsight container and the host user it runs as.
#
# The container runs with the same UID/GID as the host user `hindsight` (pinned
# IDs, fleet convention; 984 is free fleet-wide — used range 850–983). That is
# what makes the unix-socket peer auth work: postgres resolves the socket
# peer's UID against the HOST passwd, and the pg_hba default `local all all
# peer` matches the same-named PG role (created in postgres.nix).
{ config, hindsightPorts, ... }:
let
  hindsight-uid = 984;
  hindsight-gid = 984;
in
{
  users.groups.hindsight = {
    gid = hindsight-gid;
  };
  users.users.hindsight = {
    isSystemUser = true;
    group = "hindsight";
    uid = hindsight-uid;
    home = "/var/lib/hindsight";
  };

  virtualisation.oci-containers.containers.hindsight = {
    image = "ghcr.io/vectorize-io/hindsight:latest-slim";
    environment = {
      # SQLAlchemy/asyncpg-compatible libpq DSN; `?host=<dir>` = unix socket.
      HINDSIGHT_API_DATABASE_URL = "postgresql://hindsight@/hindsight?host=/var/lib/postgresql-sockets";
      HINDSIGHT_API_LLM_PROVIDER = "openrouter";
      HINDSIGHT_API_EMBEDDINGS_PROVIDER = "openrouter";
      # Verified against the embeddings API model list at wiring time; 8B is the
      # MMTEB multilingual top open-weight model and (per Alper) the cheapest.
      HINDSIGHT_API_EMBEDDINGS_OPENROUTER_MODEL = "qwen/qwen3-embedding-8b";
      # RRF = rank fusion only, no reranker model. Flip to
      # `openrouter` + HINDSIGHT_API_RERANKER_OPENROUTER_MODEL=cohere/rerank-v3.5
      # if recall quality ever disappoints.
      HINDSIGHT_API_RERANKER_PROVIDER = "rrf";
      HINDSIGHT_API_PORT = toString hindsightPorts.api;
    };
    environmentFiles = [ config.sops.secrets."hindsight_env".path ];
    user = "${toString hindsight-uid}:${toString hindsight-gid}";
    volumes = [
      "/var/lib/postgresql-sockets:/var/lib/postgresql-sockets"
    ];
    # Host networking: port binds on the host directly, tailnet reachability via
    # the firewall rule in networking.nix, WAN stays blocked (default firewall,
    # no WAN allow).
    extraOptions = [
      "--network"
      "host"
    ];
    labels = {
      "io.containers.autoupdate" = "registry";
    };
    autoStart = true;
  };

  # Socket must exist before first DB connect (hindsight retries on failure,
  # but starting in order avoids a noisy boot).
  systemd.services.${config.virtualisation.oci-containers.containers.hindsight.serviceName}.after = [
    "postgresql.service"
  ];
}
