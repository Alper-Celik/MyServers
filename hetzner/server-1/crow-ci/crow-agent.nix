{
  config,
  pkgs,
  crow-ci-args,
  ...
}:
let
  podmanUser = crow-ci-args.users.podman;
  podmanSocket = "/run/podman-crow-ci.sock";
  container = config.virtualisation.oci-containers.containers."crow-agent-local-0";
in
{
  virtualisation.oci-containers.containers."crow-agent-local-0" = {
    image = "codefloe.com/crowci/crow-agent:${crow-ci-args.tags.agent}";
    dependsOn = [ "crow-server" ];
    # container names resolve on the default podman network
    environment = {
      CROW_SERVER = "crow-server:9000";
      CROW_BACKEND = "podman";
      CROW_HOSTNAME = "local-0";
      CROW_HEALTHCHECK_ADDR = ":3010";
      CROW_AGENT_LABELS = "platform=linux/arm64,pool=local";
      CROW_LOG_LEVEL = "info";
      CROW_MAX_WORKFLOWS = "2";
    };
    volumes = [ "${podmanSocket}:/run/podman/podman.sock" ];
    # CROW_AGENT_SECRET only comes from here: a value in `environment` would be
    # passed as podman `--env`, which overrides `--env-file`
    environmentFiles = [ config.sops.templates."crow-agent-env".path ];
    labels."io.containers.autoupdate" = "registry";
  };

  sops.templates."crow-agent-env" = {
    content = ''
      CROW_AGENT_SECRET=${config.sops.placeholder.CROW_AGENT_SECRET}
    '';
    restartUnits = [ "${container.serviceName}.service" ];
  };

  systemd.sockets.podman-ci = {
    description = "Podman API Socket for crow ci";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      SocketUser = podmanUser.name;
      SocketGroup = podmanUser.name;
      ListenStream = podmanSocket;
      SocketMode = "0660";
    };
  };
  systemd.services.podman-ci = {
    description = "Podman API Service for crow ci";
    requires = [ "podman-ci.socket" ];
    after = [ "podman-ci.socket" ];
    serviceConfig = {
      KillMode = "process";
      Delegate = true;
      ExecStart = "${pkgs.podman}/bin/podman system service --time=0 unix://${podmanSocket}";
    };
  };

  users.users.${podmanUser.name} = {
    isSystemUser = true;
    uid = podmanUser.uid;
    group = podmanUser.name;
    home = "/var/lib/${podmanUser.name}";
    createHome = true;
    linger = true;
    subUidRanges = [
      {
        startUid = 5242880;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 5242880;
        count = 65536;
      }
    ];
  };
  users.groups.${podmanUser.name} = {
    gid = podmanUser.gid;
  };

}
