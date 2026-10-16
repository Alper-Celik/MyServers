{
  ...
}:
{
  imports = [
    ./crow-server.nix
    ./crow-agent.nix
    ./crow-autoscaler.nix
  ];

  _module.args.crow-ci-args = {
    # floating major image aliases: codefloe publishes `v6` for server/agent and
    # `2` for the autoscaler (no `latest`, no bare-minor aliases needed). New
    # minor/patch releases move the alias and `io.containers.autoupdate=registry`
    # pulls them on the podman-auto-update timer; bump these on a major release.
    tags = {
      server = "v6";
      agent = "v6";
      autoscaler = "2";
    };

    hosts = {
      server-host = "ci.auth.how";
      grpc-host = "crow-grpc.alper-celik.dev";
    };

    users = {
      server = {
        name = "crow-server";
        uid = 320;
        gid = 321;
      };
      podman = {
        name = "crow-podman";
        uid = 322;
        gid = 323;
      };
    };
  };

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

}
