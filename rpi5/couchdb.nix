{ config, ... }:
{
  services.couchdb = {
    enable = true;
  };

  services.nginx.virtualHosts."couchdb.lab.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    expose = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${builtins.toString config.services.couchdb.port}";
      extraConfig = ''
        proxy_redirect off;
        # proxy_buffering off;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Ssl on;
      '';
    };
  };
}
