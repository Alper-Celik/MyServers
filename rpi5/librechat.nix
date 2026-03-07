{
  config,
  lib,
  pkgs,
  ...
}:
{
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "mongodb"
    ];
  services.librechat = {
    enable = true;
    enableLocalDB = true;
    credentialsFile = config.sops.secrets.librechat_creds.path;
    env = {
      DISABLE_COMPRESSION = true;
    };
  };

  services.nginx.virtualHosts."chat.lab.alper-celik.dev" = {
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${builtins.toString config.services.librechat.env.PORT}";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
      '';
    };
  };
}
