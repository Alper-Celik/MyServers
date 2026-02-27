{ all-configs, ... }:
{
  services.nginx.virtualHosts."books.lab.alper-celik.dev" = {
    x-expose = true;
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://100.104.52.23:${builtins.toString all-configs.rpi5.config.services.calibre-web.listen.port}";
      extraConfig = ''
        client_max_body_size 500M; # Allow large book uploads

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffer_size          128k;
        proxy_buffers              4 256k;
        proxy_busy_buffers_size    256k;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        proxy_send_timeout 300s;
      '';
    };
  };

}
