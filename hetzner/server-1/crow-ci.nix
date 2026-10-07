{
  lib,
  pkgs,
  config,
  inputs,
  ...
}@args:
let
  crowGrpcHost = "crow-grpc.alper-celik.dev";
  crowUiHost = "crow.alper-celik.dev";

  # server + local agent images follow the flake's default-version; the EC2
  # agent image derives from it so all three move together on flake bumps
  crowAgentImage = "codefloe.com/crowci/crow-agent:${config.services.crowci.version}";

  # Pipeline containers must run unprivileged: the agent mounts the rootless
  # socket of a dedicated CI user instead of the host's rootful one.
  ciUser = "crow-ci";
  ciUid = 320;
  rootlessSocket = "/run/user/${toString ciUid}/podman/podman.sock";

  # The podman env-secrets below REPLACE the placeholder env values the
  # crowci-flake renders (podman applies Secret= after --env), so real secret
  # values never enter the Nix store or this public repo.
  placeholder = "sops-managed";

  # EC2 agents boot a lean Debian 13 image; the built-in autoscaler user-data
  # installs docker, so we ship our own: podman only, agent as a systemd unit.
  ec2UserData = pkgs.writeText "crow-ec2-agent-userdata" ''
    #cloud-config
    package_update: false
    packages:
      - podman
    write_files:
    - path: /etc/systemd/system/crow-agent.service
      content: |
        [Unit]
        Description=Crow CI agent
        Wants=network-online.target
        After=network-online.target podman.socket
        Requires=podman.socket
        [Service]
        ExecStartPre=/usr/bin/podman pull {{ .Image }}
        ExecStart=/usr/bin/podman run --name crow-agent --rm \
    {{ range $key, $value := .Environment }}          -e {{ $key }}={{ $value }} \
    {{ end }}          {{ .Image }}
        Restart=on-failure
        RestartSec=10s
        [Install]
        WantedBy=multi-user.target
    runcmd:
      - systemctl enable --now podman.socket
      - systemctl daemon-reload
      - systemctl start crow-agent.service
    final_message: "crow-agent up after $UPTIME seconds"
  '';

  crowPodmanSecrets = {
    crow-agent-secret = {
      secret = "CROW_AGENT_SECRET";
      file = "crow-agent-secret";
      units = [
        "crow-server.service"
        "crow-agent-local-0.service"
      ];
      target = "CROW_AGENT_SECRET";
    };
    crow-admin-token = {
      secret = "CROW_ADMIN_TOKEN";
      file = "crow-admin-token";
      units = [ "crow-autoscaler-0-aws.service" ];
      target = "CROW_TOKEN";
    };
    crow-autoscaler-token = {
      secret = "CROW_AUTOSCALER_TOKEN";
      file = "crow-autoscaler-token";
      units = [ "crow-autoscaler-0-aws.service" ];
      target = "CROW_AUTOSCALER_TOKEN";
    };
    crow-aws-region = {
      secret = "CROW_AWS_REGION";
      file = "crow-aws-region";
      units = [ "crow-autoscaler-0-aws.service" ];
      target = "CROW_AWS_REGION";
    };
    crow-aws-ami-id = {
      secret = "CROW_AWS_AMI_ID";
      file = "crow-aws-ami-id";
      units = [ "crow-autoscaler-0-aws.service" ];
      target = "CROW_AWS_AMI_ID";
    };
  };
in
{
  imports = [ inputs.crow-ci.nixosModules.default ];

  services.crowci = {
    enable = true;

    server = {
      enable = true;
      openFirewall = false;
      # caddy fronts both ports on loopback; the pod network reaches the
      # server pod-internally
      http.listen = "127.0.0.1";
      grpc.listen = "127.0.0.1";
      url = "https://${crowUiHost}";
      agentSecret = placeholder;
      # forge + OAuth app are added via the server UI instead
      settings = {
        CROW_ADMIN = "Alper-Celik";
      };
    };

    agents = [
      {
        hostnamePrefix = "local";
        replicas = 1;
        labels = {
          pool = "local";
          platform = "linux/arm64";
        };
        agentSecret = placeholder;
        podmanSocket = rootlessSocket;
        settings = {
          CROW_BACKEND_PODMAN_HOST = "unix:///run/podman/podman.sock";
          CROW_MAX_WORKFLOWS = "2";
        };
      }
    ];

    autoscaler = {
      enable = true;
      # NOTE: the flake's typed `providers` option can't eval on nixpkgs 26.05
      # (types.oneOf of submodules never falls through to the aws variant), so
      # the provider is wired via container env below instead.
      settings = {
        server = {
          url = "http://crow-server:8000";
          token = placeholder;
          autoscalerToken = placeholder;
          grpc = {
            address = "${crowGrpcHost}:443";
            secure = true;
          };
        };
        agentImage = crowAgentImage;
        agent = {
          CROW_BACKEND = "podman";
          CROW_BACKEND_PODMAN_HOST = "unix:///run/podman/podman.sock";
          CROW_AGENT_LABELS = "pool=ec2,platform=linux/amd64";
          CROW_AGENT_MAX_LIFETIME_WORKFLOWS = "1";
        };
      };
    };
  };

  users.users.${ciUser} = {
    isSystemUser = true;
    uid = ciUid;
    group = ciUser;
    home = "/var/lib/${ciUser}";
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
  users.groups.${ciUser} = { };

  # User-manager podman socket so the agent can drive rootless pipeline
  # containers; linger keeps it up without a login session.
  systemd.user.sockets.podman = {
    description = "Podman API Socket for ${ciUser}";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "%t/podman/podman.sock";
      SocketMode = "0660";
      RuntimeDirectory = "podman";
    };
  };
  systemd.user.services.podman = {
    description = "Podman API Service for ${ciUser}";
    requires = [ "podman.socket" ];
    after = [ "podman.socket" ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = "${pkgs.podman}/bin/podman system service --time=0";
    };
  };

  # The user socket may come up slightly after boot; don't race it.
  systemd.services."crow-agent-local-0".serviceConfig.ExecStartPre =
    pkgs.writeShellScript "wait-crow-rootless-socket" ''
      for i in $(seq 1 60); do
        [ -S ${rootlessSocket} ] && exit 0
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "rootless podman socket ${rootlessSocket} never appeared" >&2
      exit 1
    '';

  virtualisation.quadlet.containers."crow-server".containerConfig.secrets = lib.mapAttrsToList (
    _: v: "${v.file},type=env,target=${v.target}"
  ) (lib.filterAttrs (_: v: lib.elem "crow-server.service" v.units) crowPodmanSecrets);

  virtualisation.quadlet.containers."crow-agent-local-0".containerConfig.secrets =
    lib.mapAttrsToList (_: v: "${v.file},type=env,target=${v.target}")
      (lib.filterAttrs (_: v: lib.elem "crow-agent-local-0.service" v.units) crowPodmanSecrets);

  # the flake only generates autoscaler containers per provider entry, and
  # its `providers` option can't eval on nixpkgs 26.05 (types.oneOf of
  # submodules never falls through to the aws variant), so this container is
  # defined here and the provider is wired via env instead
  virtualisation.quadlet.containers."crow-autoscaler-0-aws".containerConfig = {
    image = "codefloe.com/crowci/crow-autoscaler:latest";
    pod = "crow.pod";
    autoUpdate = "registry";
    secrets = lib.mapAttrsToList (_: v: "${v.file},type=env,target=${v.target}") (
      lib.filterAttrs (_: v: lib.elem "crow-autoscaler-0-aws.service" v.units) crowPodmanSecrets
    );
    environmentFiles = [ config.sops.templates."crow-aws-env".path ];
    environments = {
      # the flake's AWS provider submodule does not expose these flags
      CROW_PROVIDER = "aws";
      CROW_AWS_INSTANCE_TYPE = "m8i.8xlarge";
      CROW_AWS_USE_SPOT_INSTANCES = "true";
      CROW_AWS_SPOT_FALLBACK_ON_DEMAND = "true";
      CROW_MIN_AGENTS = "0";
      CROW_MAX_AGENTS = "2";
      CROW_WORKFLOWS_PER_AGENT = "4";
      CROW_POOL_ID = "1";
      # mandatory with any future second autoscaler: without it every
      # autoscaler counts all pending tasks and over-provisions
      CROW_FILTER_LABELS = "pool=huge-amd64";
      CROW_AGENT_IDLE_TIMEOUT = "5m";
      CROW_PROVIDER_USERDATA_FILE = "/etc/crow/userdata.yaml";
    };
    volumes = [ "${ec2UserData}:/etc/crow/userdata.yaml:ro" ];
  };

  systemd.services.crow-podman-secrets = {
    description = "Register crowci podman secrets from sops-rendered files";
    after = [ "sops-nix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script =
      let
        podman = "${pkgs.podman}/bin/podman";
        register = name: value: ''
          ${podman} secret create --replace ${name} ${config.sops.templates.${value.file}.path}
        '';
      in
      lib.concatStrings (lib.mapAttrsToList register crowPodmanSecrets);
  };

  # crow units need the podman secrets to exist before they start
  systemd.services."crow-server".requires = [ "crow-podman-secrets.service" ];
  systemd.services."crow-server".after = [ "crow-podman-secrets.service" ];
  systemd.services."crow-agent-local-0".requires = [
    "crow-podman-secrets.service"
  ];
  systemd.services."crow-agent-local-0".after = [
    "crow-podman-secrets.service"
  ];
  systemd.services."crow-autoscaler-0-aws".requires = [
    "crow-podman-secrets.service"
  ];
  systemd.services."crow-autoscaler-0-aws".after = [
    "crow-podman-secrets.service"
  ];

  sops.secrets = {
    CROW_AGENT_SECRET = { };
    CROW_ADMIN_TOKEN = { };
    CROW_AUTOSCALER_TOKEN = { };
    CROW_AWS_ACCESS_KEY_ID = { };
    CROW_AWS_SECRET_ACCESS_KEY = { };
    CROW_AWS_REGION = { };
    CROW_AWS_AMI_ID = { };
    CROW_AWS_SUBNETS = { };
    CROW_AWS_SECURITY_GROUPS = { };
    CROW_AWS_SSH_KEYNAME = { };
  };

  sops.templates =
    (builtins.mapAttrs (_: v: {
      content = config.sops.placeholder.${v.secret};
      path = "/run/crow-ci/${v.file}";
      restartUnits = [ "crow-podman-secrets.service" ] ++ v.units;
    }) crowPodmanSecrets)
    // {
      "crow-aws-env" = {
        content = ''
          AWS_ACCESS_KEY_ID=${config.sops.placeholder.CROW_AWS_ACCESS_KEY_ID}
          AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.CROW_AWS_SECRET_ACCESS_KEY}
          CROW_AWS_SUBNETS=${config.sops.placeholder.CROW_AWS_SUBNETS}
          CROW_AWS_SECURITY_GROUPS=${config.sops.placeholder.CROW_AWS_SECURITY_GROUPS}
          CROW_AWS_SSH_KEYNAME=${config.sops.placeholder.CROW_AWS_SSH_KEYNAME}
          CROW_AWS_SPOT_FALLBACK_ON_DEMAND=true
          CROW_POOL_ID=1
          CROW_FILTER_LABELS=pool=ec2
          CROW_AGENT_IDLE_TIMEOUT=5m
        '';
        owner = "root";
        restartUnits = [
          "crow-podman-secrets.service"
          "crow-autoscaler-0-aws.service"
        ];
      };
    };

  services.caddy.virtualHosts = {
    # public: GitHub webhook delivery and OAuth redirects come from outside
    # the tailnet (PR CI on public repos)
    ${crowUiHost} = {
      x-expose = true;
      extraConfig = "reverse_proxy http://127.0.0.1:8000";
    };
    ${crowGrpcHost} = {
      x-expose = true;
      extraConfig = "reverse_proxy h2c://127.0.0.1:9000";
    };
  };
}
