{
  lib,
  pkgs,
  config,
  inputs,
  postgresSocketDir,
  crow-ci-args,
  ...
}:
{
  users = {
    groups.${crow-ci-args.users.server.name}.gid = crow-ci-args.users.server.gid;
    users.${crow-ci-args.users.server.name} = {
      isSystemUser = true;
      uid = crow-ci-args.users.server.uid;
      group = crow-ci-args.users.server.name;
    };
  };

  services.postgresql = {
    ensureDatabases = [ crow-ci-args.users.server.name ];
    ensureUsers = [
      {
        name = crow-ci-args.users.server.name;
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
  };

  services.crowci = {
    enable = true;

    server = {
      enable = true;
      openFirewall = false;
      http.listen = "127.0.0.1";
      grpc.listen = "127.0.0.1";
      # the env file below (systemd applies EnvironmentFile= over Environment=)
      agentSecret = "sops-managed";
      settings = {
        CROW_ADMIN = "Alper-Celik";
        CROW_DATABASE_DRIVER = "postgres";
        CROW_DATABASE_DATASOURCE = "postgres://${crow-ci-args.users.server.name}@/${crow-ci-args.users.server.name}?host=${postgresSocketDir}";
      };
    };
  };

  virtualisation.quadlet.containers."crow-server".containerConfig = {
    user = "${toString crow-ci-args.users.server.uid}:${toString crow-ci-args.users.server.gid}";
    volumes = [ "${postgresSocketDir}:${postgresSocketDir}" ];
    environmentFiles = [ config.sops.templates.crow-server.path ];
  };

  sops.templates.crow-server = {
    content = ''
      CROW_AGENT_SECRET=${config.sops.placeholder.CROW_AGENT_SECRET}
    '';
    restartUnits = [
      "crow-server.service"
    ];
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
