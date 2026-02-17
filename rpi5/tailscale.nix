{ config, ... }:
{
  services.tailscale = {
    useRoutingFeatures = "both";
    extraSetFlags = [ "--advertise-exit-node" ];
    extraUpFlags = [
      "--advertise-exit-node"
      "--snat-subnet-routes=false"
      "--advertise-routes=172.25.42.0/24"
    ];
    enable = true;
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
  };
}
