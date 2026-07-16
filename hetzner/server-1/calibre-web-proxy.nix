{ all-configs, ... }:
{
  services.caddy.virtualHosts."books.lab.alper-celik.dev" = {
    x-expose = true;
    extraConfig = "reverse_proxy http://100.104.52.23:${toString all-configs.rpi5.config.services.calibre-web.listen.port}";
  };
}
