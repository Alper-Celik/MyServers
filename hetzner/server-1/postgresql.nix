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
}
