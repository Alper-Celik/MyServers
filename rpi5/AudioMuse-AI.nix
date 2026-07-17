{
  config,
  lib,
  ...
}:
let
  pg_db_name = "audiomuse";
  pg_port = config.services.postgresql.settings.port;
  shared_env = {
    MEDIASERVER_TYPE = "jellyfin";
    JELLYFIN_URL = "https://jellyfin.lab.alper-celik.dev";
    TZ = "Europe/Istanbul";
    POSTGRES_USER = pg_db_name;
    POSTGRES_DB = pg_db_name;
    POSTGRES_HOST = "host.containers.internal";
    POSTGRES_PORT = builtins.toString pg_port;
    REDIS_URL = "redis://host.containers.internal:6380/0";
    REDIS_PORT = "6380";
    CLAP_ENABLED = "true";
    TEMP_DIR = "/app/temp_audio";
    WORKER_PORT = "8898";
    NUMBA_CACHE_DIR = "/tmp";
  };
  db_deps = [
    "postgresql.service"
    "redis-audiomuse.service"
  ];

in
{
  users = {
    groups.audiomuse = {
      gid = 977;
    };
    users.audiomuse = {
      uid = 982;
      isSystemUser = true;
      group = config.users.groups.audiomuse.name;
    };

  };
  networking.firewall.trustedInterfaces = [ "podman0" ];
  services.postgresql = {
    enableTCPIP = true;
    ensureDatabases = [ pg_db_name ];
    ensureUsers = [
      {
        name = pg_db_name;
        ensureDBOwnership = true;
      }
    ];
    authentication = lib.mkAfter ''
      # type    database      user          address           method
      host      audiomuse     audiomuse     10.88.0.0/16      scram-sha-256
    '';
  };
  services.redis.servers.audiomuse = {
    user = "audiomuse";
    enable = true;
    port = 6380;
    settings.bind = lib.mkForce "127.0.0.1 10.88.0.1";
    settings.protected-mode = "no";
  };

  systemd.services = {
    ${config.virtualisation.oci-containers.containers.audiomuse-worker.serviceName} = {
      after = db_deps;
    };
    ${config.virtualisation.oci-containers.containers.audiomuse-flask.serviceName} = {
      after = db_deps;
    };
  };

  virtualisation.oci-containers.containers = {

    audiomuse-flask = {
      image = "ghcr.io/neptunehub/audiomuse-ai:latest";
      user = "982:977";
      volumes = [
        "temp-audio-flask:/app/temp_audio"
      ];
      environment = shared_env // {
        SERVICE_TYPE = "flask";
      };
      environmentFiles = [ config.sops.secrets.audiomuse_env.path ];
      ports = [
        "8980:8000"
      ];
      autoStart = true;
    };

    audiomuse-worker = {
      image = "ghcr.io/neptunehub/audiomuse-ai:latest";
      user = "982:977";
      volumes = [
        "temp-audio-worker:/app/temp_audio"
      ];
      environment = shared_env // {
        SERVICE_TYPE = "worker";
      };
      environmentFiles = [ config.sops.secrets.audiomuse_env.path ];
      autoStart = true;
    };
  };

  services.nginx.virtualHosts."audiomuse.lab.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8980";
    };
  };

}
