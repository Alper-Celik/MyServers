{ ... }: {
  services.caddy.virtualHosts."beta.ym-pdf.alper-celik.dev" = {
    x-expose = true;
    extraConfig = ''
      root /var/lib/www/beta.ym-pdf.alper-celik.dev
      file_server browse
    '';
  };
}
