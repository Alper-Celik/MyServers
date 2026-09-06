{ ... }:
{
  virtualisation = {
    oci-containers = {
      backend = "podman";
    };
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
      autoPrune = {
        enable = true;
        dates = "daily";
      };
    };
  };
  systemd.timers."podman-auto-update".wantedBy = [ "timers.target" ];
}
