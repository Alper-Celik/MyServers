{ config, ... }:
{
  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
    extraUpFlags = [ "--advertise-exit-node" ];
    enable = true;
    authKeyFile = config.sops.secrets.tailscale-rpi5.path;
  };
}
