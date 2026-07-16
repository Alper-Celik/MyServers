{ ... }:
{
  services.caddy.virtualHosts."fileshare.alper-celik.dev" = {
    x-expose = true;
    extraConfig = ''
      root /var/lib/fileshare
      file_server browse
    '';
  };

  services.caddy.virtualHosts."cv-redirect.alper-celik.dev" = {
    x-expose = true;
    extraConfig = "redir https://fileshare.alper-celik.dev/cv%20resources/cv.pdf permanent";
  };
}
