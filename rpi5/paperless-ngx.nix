{ config, ... }:
{
  services.paperless = {
    enable = true;
    configureTika = true;
    database.createLocally = true;

    settings = {
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
      ];
      PAPERLESS_OCR_LANGUAGE = "tur+eng";
      PAPERLESS_URL = "documents.lab.alper-celik.dev";
      PAPERLESS_USE_X_FORWARD_HOST = true;
      PAPERLESS_USE_X_FORWARD_PORT = true;
      PAPERLESS_PROXY_SSL_HEADER = [
        "HTTP_X_FORWARDED_PROTO"
        "https"
      ];
    };
  };

  services.nginx.virtualHosts."${config.services.paperless.settings.PAPERLESS_URL}" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;

    locations."/" = {
      proxyWebsockets = true;
      proxyPass = "http://127.0.0.1:${toString config.services.paperless.port}";
      extraConfig = ''
        # allow large file uploads
        client_max_body_size 1024M;

        proxy_redirect off;
        proxy_set_header Host $host:$server_port;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host $server_name;
        proxy_set_header X-Forwarded-Proto $scheme;
        add_header Referrer-Policy "strict-origin-when-cross-origin";
      '';
    };

  };
}
