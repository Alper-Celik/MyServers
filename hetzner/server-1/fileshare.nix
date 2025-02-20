{ config, ... }:
{
  services.nginx.virtualHosts."fileshare.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:18080";
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

  services.nginx.virtualHosts."cv-redirect.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    locations."/" = {
      return = "301 https://fileshare.alper-celik.dev/cv%20resources/cv.pdf";
    };
  };
}
