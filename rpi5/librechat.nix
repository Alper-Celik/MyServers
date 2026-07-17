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
      "mongodb-ce"
    ];
  services.mongodb.package = pkgs.mongodb-ce;
  services.librechat = {
    enable = true;
    enableLocalDB = true;
    credentialsFile = config.sops.secrets.librechat_creds.path;
    env = {
      DISABLE_COMPRESSION = true;
    };
  };

  services.caddy.virtualHosts."chat.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://[::1]:${toString config.services.librechat.env.PORT}";
  };
}
