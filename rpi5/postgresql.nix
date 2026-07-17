{
  config,
  pkgs,
  lib,
  ...
}:
{

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 5432 ];
  networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ 5432 ];
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    enableJIT = true;
  };

  services.pgadmin = {
    enable = true;
    initialEmail = "alper@alper-celik.dev";
    initialPasswordFile = config.sops.secrets.pgadmin-pass.path;
  };
  systemd.services.pgadmin.serviceConfig.TimeoutStartSec = "10min";

  services.caddy.virtualHosts."pgadmin.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString config.services.pgadmin.port}";
  };

}
