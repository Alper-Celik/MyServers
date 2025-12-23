{
  config,
  ...
}:
{
  boot.kernel.sysctl."net.ipv4.ip_forward" = true; # 1
  virtualisation.docker.enable = true;
  services.gitlab-runner = {
    enable = true;
    services = {
      autocode-alper = {
        authenticationTokenConfigFile = config.sops.secrets.GITLAB_RUNNER_AUTOCODE.path;
        dockerImage = "ubuntu";
      };
    };
  };
}
