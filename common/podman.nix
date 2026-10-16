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
        # podman system prune -f alone keeps tagged images no container
        # references; pipeline images pulled through the crow agent's socket
        # accumulate without this. Volumes are still never pruned.
        flags = [ "--all" ];
      };
    };
  };
  systemd.timers."podman-auto-update".wantedBy = [ "timers.target" ];
}
