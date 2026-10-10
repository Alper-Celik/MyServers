{
  inputs,
  ...
}:

{
  imports = [
    ./crow-ci.nix
    ./crow-server.nix
    ./crow-agent.nix
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

  _module.args.crow-ci-args = {
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
      runner = {

      };
    };

  };
}
