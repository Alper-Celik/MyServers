{ ... }:
{
  networking.hostName = "hetzner-server-1";
  networking.useNetworkd = true;
  systemd.network = {
    enable = true;
    networks."30-wan" = {
      matchConfig.Name = "enp1s0";
      networkConfig.DHCP = "no";
      address = [
        "168.119.172.112/32"
        "2a01:4f8:c0c:57f0::1/64"
      ];
      routes = [
        {
          Gateway = "172.31.1.1";
          GatewayOnLink = true;
        }
        { Gateway = "fe80::1"; }
      ];
    };
  };
}
