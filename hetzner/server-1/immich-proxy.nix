{ all-configs, ... }:
{
  services.nginx.virtualHosts."photos.lab.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;

    expose = true;

    locations."/" = {
      proxyWebsockets = true;
      proxyPass = "http://100.104.52.23:${toString all-configs.rpi5.config.services.immich.port}";
      extraConfig = ''
        # allow large file uploads
        client_max_body_size 50000M;

        # Set headers
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # set timeout
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        send_timeout       600s;
      '';
    };
  };

}
