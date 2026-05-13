{ inputs, ... }:

{
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv4.conf.enp1s0.proxy_arp" = 1;
  };
  services.ndppd = {
    enable = true;
    proxies.enp1s0.rules."2a01:4f8:c0c:57f0::/64" = { };
  };
  boot.enableContainers = true;
  virtualisation.containers.enable = true;
  containers.riscv-tr = {
    timeoutStartSec = "30m";
    autoStart = true;
    privateNetwork = true;

    hostAddress = "192.168.100.1";
    localAddress = "116.202.186.49";

    hostAddress6 = "2a01:4f8:c0c:57f0::ff";
    localAddress6 = "2a01:4f8:c0c:57f0::2";

    path = inputs.riscv-tr.nixosConfigurations."riscv-tr-1".config.system.build.toplevel;
  };
}
