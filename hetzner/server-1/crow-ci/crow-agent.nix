{
  lib,
  pkgs,
  config,
  inputs,
  postgresSocketDir,
  crow-ci-args,
  ...
}@args:

let
  # systemd applies EnvironmentFile= over Environment=, so this inert value
  # (required by the flake's agent option) is overridden by the real secret
  # in the env file below
  agentSecret = "sops-managed";
in
{
  services.crowci = {
    agents = [
      {
        server = crow-ci-args.hosts.grpc-host;
        podmanSocket = "/run/podman-crow-ci.sock";
        hostnamePrefix = "local";
        agentSecret = agentSecret;
        replicas = 1;
        labels = {
          pool = "local";
          platform = "linux/arm64";
        };
        settings = {
          CROW_MAX_WORKFLOWS = "3";
        };
      }
    ];
  };

  # agent secret as a plain env file; sops re-renders and restarts the agent
  # container when the secret changes
  virtualisation.quadlet.containers."crow-agent-local-0".containerConfig.environmentFiles = [
    config.sops.templates.crow-agent-env.path
  ];

  sops.templates.crow-agent-env = {
    content = ''
      CROW_AGENT_SECRET=${config.sops.placeholder.CROW_AGENT_SECRET}
    '';
    restartUnits = [ "crow-agent-local-0.service" ];
  };

  systemd.sockets.podman-ci = {
    description = "Podman API Socket for crow ci";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      SocketUser = crow-ci-args.users.podman.name;
      SocketGroup = crow-ci-args.users.podman.name;
      ListenStream = "/run/podman-crow-ci.sock";
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
      ExecStart = "${pkgs.podman}/bin/podman system service --time=0 unix:///run/podman-crow-ci.sock";
    };
  };

  users.users.${crow-ci-args.users.podman.name} = {
    isSystemUser = true;
    uid = crow-ci-args.users.podman.uid;
    group = crow-ci-args.users.podman.name;
    home = "/var/lib/${crow-ci-args.users.podman.name}";
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
  users.groups.${crow-ci-args.users.podman.name} = {
    gid = crow-ci-args.users.podman.gid;
  };

}
