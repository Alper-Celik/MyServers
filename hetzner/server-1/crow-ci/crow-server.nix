{
  config,
  crow-ci-args,
  postgresSocketDir,
  ...
}:
let
  server = crow-ci-args.users.server;
  container = config.virtualisation.oci-containers.containers."crow-server";
in
{
  users = {
    groups.${server.name}.gid = server.gid;
    users.${server.name} = {
      isSystemUser = true;
      uid = server.uid;
      group = server.name;
    };
  };

  services.postgresql = {
    ensureDatabases = [ server.name ];
    ensureUsers = [
      {
        name = server.name;
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
  };

  # crow stores its state here; the container runs as the crow-server user, so
  # the bind source has to be owned by it
  systemd.tmpfiles.rules = [
    "d /var/lib/crowci-server 0700 ${toString server.uid} ${toString server.gid} -"
  ];

  virtualisation.oci-containers.containers."crow-server" = {
    image = "codefloe.com/crowci/crow-server:${crow-ci-args.tags.server}";
    user = "${toString server.uid}:${toString server.gid}";
    # caddy fronts both ports on loopback
    ports = [
      "127.0.0.1:8000:8000/tcp"
      "127.0.0.1:9000:9000/tcp"
    ];
    volumes = [
      "/var/lib/crowci-server:/var/lib/crow"
      "${postgresSocketDir}:${postgresSocketDir}"
    ];
    # CROW_AGENT_SECRET only comes from here: a value in `environment` would be
    # passed as podman `--env`, which overrides `--env-file`
    environmentFiles = [ config.sops.templates."crow-server".path ];
    labels."io.containers.autoupdate" = "registry";
    environment = {
      CROW_HOST = "https://${crow-ci-args.hosts.server-host}";
      CROW_SERVER_ADDR = ":8000";
      CROW_GRPC_ADDR = ":9000";
      CROW_OPEN = "false";
      CROW_LOG_LEVEL = "info";
      CROW_ADMIN = "Alper-Celik";
      CROW_DATABASE_DRIVER = "postgres";
      CROW_DATABASE_DATASOURCE = "postgres://${server.name}@/${server.name}?host=${postgresSocketDir}";
      CROW_FORGES = "forgejoe";
      CROW_FORGE_FORGEJOE_TYPE = "forgejo";
      CROW_FORGE_FORGEJOE_URL = "https://git.auth.how";
    };
  };

  sops.templates."crow-server" = {
    content = ''
      CROW_AGENT_SECRET=${config.sops.placeholder.CROW_AGENT_SECRET}
      CROW_FORGE_FORGEJOE_CLIENT=${config.sops.placeholder.CROW_FORGE_FORGEJOE_CLIENT}
      CROW_FORGE_FORGEJOE_SECRET=${config.sops.placeholder.CROW_FORGE_FORGEJOE_SECRET}
    '';
    restartUnits = [ "${container.serviceName}.service" ];
  };

  services.caddy.virtualHosts = {
    ${crow-ci-args.hosts.server-host} = {
      x-expose = true;
      extraConfig = "reverse_proxy http://127.0.0.1:8000";
    };
    ${crow-ci-args.hosts.grpc-host} = {
      x-expose = true;
      extraConfig = "reverse_proxy h2c://127.0.0.1:9000";
    };
  };

}
