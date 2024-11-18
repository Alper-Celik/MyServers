{ config, ... }:
{
  services.tailscale = {
    useRoutingFeatures = "both";
    extraSetFlags = [ "--advertise-exit-node" ];
    extraUpFlags = [
      "--advertise-exit-node"
      "--advertise-routes=192.168.1.0/24"
    ];
    enable = true;
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
  };
}
