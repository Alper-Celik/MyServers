{
  config,
  pkgs,
  crow-ci-args,
  ...
}:
let
  podmanUser = crow-ci-args.users.podman;
  runtimeDir = "/run/user/${toString podmanUser.uid}";
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
      # the in-container stat probe for the socket fails here; naming it
      # explicitly short-circuits that (same env the spawned EC2 agents get)
      CROW_BACKEND_PODMAN_HOST = "unix:///run/podman/podman.sock";
      CROW_HOSTNAME = "local-0";
      CROW_HEALTHCHECK_ADDR = ":3010";
      CROW_AGENT_LABELS = "platform=linux/arm64,pool=local";
      CROW_LOG_LEVEL = "info";
      CROW_MAX_WORKFLOWS = "2";
    };
    # the socket file lives in the crow-podman user's runtime dir: pipeline
    # steps are rootless containers under that user's subuid range, not host
    # root. A file mount pins its inode - a podman-ci restart changes the
    # inode, so the agent unit is lifecycle-coupled to the service below (and
    # unit recreation on every deploy covers the boot case).
    volumes = [ "${runtimeDir}/podman/podman.sock:/run/podman/podman.sock" ];
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

  # Rootless podman API service: runs as crow-podman against its own store
  # (/var/lib/crow-podman), so every step container executes without host
  # root. The service binds its own socket in the user's runtime dir - there
  # is deliberately no systemd socket unit, so nothing recreates or unlinks
  # the node behind the container's file mount. Type=notify keeps the agent's
  # After= ordering honest: the socket exists before dependents start.
  systemd.services.podman-ci = {
    description = "Rootless Podman API Service for crow ci";
    after = [ "user-runtime-dir@${toString podmanUser.uid}.service" ];
    requires = [ "user-runtime-dir@${toString podmanUser.uid}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = podmanUser.name;
      Type = "notify";
      TimeoutStartSec = "90s";
      KillMode = "process";
      Delegate = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStart = "${pkgs.podman}/bin/podman system service --time=0";
      Environment = [
        "HOME=/var/lib/${podmanUser.name}"
        "XDG_RUNTIME_DIR=${runtimeDir}"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=${runtimeDir}/bus"
      ];
    };
  };

  # the socket file mount pins the inode: a podman-ci restart must stop and
  # restart the agent, or the agent stares at a dead socket node.
  systemd.services.${container.serviceName} = {
    after = [ "podman-ci.service" ];
    requires = [ "podman-ci.service" ];
    partOf = [ "podman-ci.service" ];
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
