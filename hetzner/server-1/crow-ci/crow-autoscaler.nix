{

  crow-ci-args,
  config,
  ...
}:
{
  services.crowci = {
    autoscaler = {
      enable = true;
      settings = {
        server = {
          url = "http://crow-server:8000";
          token = placeholder;
          autoscalerToken = placeholder;
          grpc = {
            address = "${crow-ci-args.hosts.grpc-host}:443";
            secure = true;
          };
        };
        agent = {
          CROW_BACKEND = "podman";
          CROW_BACKEND_PODMAN_HOST = "unix:///run/podman/podman.sock";
          CROW_AGENT_LABELS = "pool=ec2,platform=linux/amd64";
          CROW_AGENT_MAX_LIFETIME_WORKFLOWS = "1";
        };
      };
      providers = [
        {
          type = "aws";
          instanceType = "m8i.8xlarge";
          min = 0;
          max = 3;
          workflowsPerAgent = 4;
        }
      ];
    };
  };
  virtualisation.quadlet.containers."crow-autoscaler-0-aws".containerConfig = {
    environmentFiles = [ config.sops.templates."crow-aws-env".path ];
    environments = {
      CROW_AWS_USE_SPOT_INSTANCES = "true";
      CROW_AWS_SPOT_FALLBACK_ON_DEMAND = "true";
      CROW_POOL_ID = "1";
      CROW_FILTER_LABELS = "pool=huge-amd64";
      CROW_AGENT_IDLE_TIMEOUT = "5m";
      CROW_PROVIDER_USERDATA_FILE = "/etc/crow/userdata.yaml";
    };
  };
  sops.templates = {
    "crow-aws-env" = {
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder.CROW_AWS_ACCESS_KEY_ID}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.CROW_AWS_SECRET_ACCESS_KEY}
        CROW_AWS_SUBNETS=${config.sops.placeholder.CROW_AWS_SUBNETS}
        CROW_AWS_SECURITY_GROUPS=${config.sops.placeholder.CROW_AWS_SECURITY_GROUPS}
        CROW_AWS_SSH_KEYNAME=${config.sops.placeholder.CROW_AWS_SSH_KEYNAME}
      '';
      owner = "root";
      restartUnits = [
        "crow-autoscaler-0-aws.service"
      ];
    };
  };

}
