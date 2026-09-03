{ config, ... }:
{
  services.tailscale = {
    useRoutingFeatures = "both";
    extraSetFlags = [ "--advertise-exit-node" ];
    extraUpFlags = [
      "--advertise-exit-node"
    ];
    enable = true;
  };
}
