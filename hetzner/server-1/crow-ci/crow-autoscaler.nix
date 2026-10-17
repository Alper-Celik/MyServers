{
  config,
  pkgs,
  crow-ci-args,
  ...
}:
let
  container = config.virtualisation.oci-containers.containers."crow-autoscaler-0-aws";

  crowAgentImage = "codefloe.com/crowci/crow-agent:${crow-ci-args.tags.agent}";

  # values may be strings, ints or bools; builtins.toString renders booleans as
  # "1"/"" , so those are rendered explicitly
  renderEnvValue = v: if builtins.isBool v then (if v then "true" else "false") else toString v;

  # CROW_AGENT_ENV is a comma-separated KEY=value list handed to every agent the
  # autoscaler spawns. Attributes are sorted, which keeps the label fragments
  # right after CROW_AGENT_LABELS: the autoscaler re-absorbs lower-case
  # `key=value` items that follow it as more labels rather than new variables.
  mkAgentEnv =
    attrs:
    builtins.concatStringsSep "," (
      builtins.map (k: "${k}=${renderEnvValue attrs.${k}}") (builtins.attrNames attrs)
    );

  # EC2 agents boot a lean Debian 13 image; the autoscaler's built-in user-data
  # installs docker, so we ship our own: podman only, agent as a systemd unit
  # that mounts the VM's podman socket for pipeline containers.
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
          -v /run/podman/podman.sock:/run/podman/podman.sock \
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
in
{
  virtualisation.oci-containers.containers."crow-autoscaler-0-aws" = {
    image = "codefloe.com/crowci/crow-autoscaler:${crow-ci-args.tags.autoscaler}";
    dependsOn = [ "crow-server" ];
    labels."io.containers.autoupdate" = "registry";
    volumes = [ "${ec2UserData}:/etc/crow/userdata.yaml:ro" ];
    # tokens and AWS credentials come from here: a value in `environment` would
    # be passed as podman `--env`, which overrides `--env-file`
    environmentFiles = [ config.sops.templates."crow-autoscaler-env".path ];
    environment = {
      CROW_SERVER = "http://crow-server:8000";
      CROW_GRPC_ADDR = "${crow-ci-args.hosts.grpc-host}:443";
      CROW_GRPC_SECURE = "true";

      CROW_PROVIDER = "aws";
      CROW_MIN_AGENTS = "0";
      CROW_MAX_AGENTS = "3";
      CROW_WORKFLOWS_PER_AGENT = "4";
      CROW_AGENT_IDLE_TIMEOUT = "5m";
      CROW_POOL_ID = "1";
      CROW_FILTER_LABELS = "pool=huge-amd64";
      CROW_AGENT_IMAGE = crowAgentImage;

      CROW_AGENT_ENV = mkAgentEnv {
        CROW_AGENT_LABELS = "pool=huge-amd64,platform=linux/amd64";
        CROW_AGENT_MAX_LIFETIME_WORKFLOWS = 1;
        CROW_BACKEND = "podman";
        CROW_BACKEND_PODMAN_HOST = "unix:///run/podman/podman.sock";
        # spawned agents reach the server through the TLS-terminating grpc
        # proxy: the autoscaler does not forward its own CROW_GRPC_* settings
        CROW_GRPC_SECURE = true;
      };

      CROW_AWS_INSTANCE_TYPE = "m8i.8xlarge";
      CROW_AWS_USE_SPOT_INSTANCES = "true";
      CROW_AWS_SPOT_FALLBACK_ON_DEMAND = "true";
      CROW_PROVIDER_USERDATA_FILE = "/etc/crow/userdata.yaml";
    };
  };

  sops.templates."crow-autoscaler-env" = {
    content = ''
      CROW_TOKEN=${config.sops.placeholder.CROW_ADMIN_TOKEN}
      CROW_AUTOSCALER_TOKEN=${config.sops.placeholder.CROW_AUTOSCALER_TOKEN}
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.CROW_AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.CROW_AWS_SECRET_ACCESS_KEY}
      CROW_AWS_REGION=${config.sops.placeholder.CROW_AWS_REGION}
      CROW_AWS_AMI_ID=${config.sops.placeholder.CROW_AWS_AMI_ID}
      CROW_AWS_SUBNETS=${config.sops.placeholder.CROW_AWS_SUBNETS}
      CROW_AWS_SECURITY_GROUPS=${config.sops.placeholder.CROW_AWS_SECURITY_GROUPS}
      CROW_AWS_SSH_KEYNAME=${config.sops.placeholder.CROW_AWS_SSH_KEYNAME}
    '';
    owner = "root";
    restartUnits = [ "${container.serviceName}.service" ];
  };

}
