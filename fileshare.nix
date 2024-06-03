{ ... }:
{
  services.nginx = {
    enable = true;
    virtualHosts."fileshare.alper-celik.dev" = {
      enableACME = true;
      forceSSL = true;
      root = "/var/www/fileshare";
    };
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "alper@alper-celik.dev";
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 80 443 ];

}
