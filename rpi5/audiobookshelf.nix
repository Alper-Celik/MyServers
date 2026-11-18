{
  config,
  ...
}:
{
  services.audiobookshelf = {
    enable = true;
    # loopback only; caddy fronts the tailnet vhost
    host = "127.0.0.1";
    port = 8000;
  };

  # the library is read through the multimedia overlay; rpi5/multimedia.nix
  # grants the user its ACL entry there
  systemd.services.audiobookshelf.after = [ "var-lib-multimedia-media.mount" ];

  services.caddy.virtualHosts."audiobooks.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString config.services.audiobookshelf.port}";
  };
}
