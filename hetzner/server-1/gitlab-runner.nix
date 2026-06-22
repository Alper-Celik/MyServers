{
  config,
  pkgs,
  ...
}:
{
  boot.kernel.sysctl."net.ipv4.ip_forward" = true; # 1
  virtualisation.docker = {
    package = pkgs.docker_29;
    enable = true;
  };
  services.gitlab-runner = {
    enable = true;
    services = {
      autocode-alper = {
        authenticationTokenConfigFile = config.sops.secrets.GITLAB_RUNNER_AUTOCODE.path;
        dockerImage = "ubuntu";
        dockerPrivileged = true;
        environmentVariables = {
          FF_NETWORK_PER_BUILD = "1";
        };
      };
    };
  };
}
