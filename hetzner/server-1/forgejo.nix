{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.forgejo;
  srv = cfg.settings.server;
in
{
  services.nginx = {
    virtualHosts.${cfg.settings.server.DOMAIN} = {
      x-expose = true;
      forceSSL = true;
      enableACME = true;
      extraConfig = ''
        client_max_body_size 512M;
      '';
      locations."/".proxyPass = "http://localhost:${toString srv.HTTP_PORT}";
    };
  };

  services.forgejo = {
    enable = true;
    database.type = "postgres";

    lfs.enable = true;

    settings = {
      server = {
        DOMAIN = "git.alper-celik.dev";
        ROOT_URL = "https://${srv.DOMAIN}/";
        HTTP_PORT = 3030;
      };
      service.DISABLE_REGISTRATION = true;
    };
  };

  services.openssh.settings.AcceptEnv = "GIT_PROTOCOL";
}
