{ config, ... }:
{
  services.tailscale = {
    useRoutingFeatures = "both";
    extraSetFlags = [ "--advertise-exit-node" ];
    extraUpFlags = [
      "--advertise-exit-node"
    ];
    enable = true;
    authKeyFile = config.sops.secrets.tailscale-auth-key-hetzner-server-1.path;
  };
}
