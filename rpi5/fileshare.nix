{ config, ... }:
{
  services.nginx.virtualHosts."fileshare.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    expose = true;
    locations."/" = {
      proxyPass = "http://localhost:18080";
      # root = "/var/lib/fileshare";
      # extraConfig = ''
      #   autoindex on;
      # '';
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts."http://fileshare.alper-celik.dev" = {
      extraConfig = ''
        root /var/lib/fileshare
        file_server browse
      '';
    };
    globalConfig = ''
        http_port    18080
      	https_port   44380
    '';
  };
}
