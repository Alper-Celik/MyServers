{ ... }: {
  services.tailscale.enable = true;
  networking = {
    hostName = "ovhcloud-server-1";
    useNetworkd = true;
    useDHCP = false;
  };
  systemd.network = {
    enable = true;
    networks."30-wan" = {
      enable = true;
      matchConfig.Name = "ens3";
      DHCP = "no";
      address = [
        "57.131.137.204/32"
        "2001:41d0:701:1100::42/64"
      ];
      routes = [
        {
          Gateway = "57.131.137.1";
          GatewayOnLink = true;
        }
        {
          Gateway = "2001:41d0:701:1100::42/64";
          GatewayOnLink = true;
        }
      ];
    };
  };
}
