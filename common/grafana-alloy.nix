{ lib, config, ... }:
# lib.mkIf config.services.alloy.enable
{

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 12345 ];
  users = {
    users.alloy = {
      isSystemUser = true;
      group = "alloy";
      extraGroups = [
        "messagebus"

        # for journal see https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/
        "adm"
        "systemd-journal"
      ];
    };
    groups.alloy = { };
  };

  systemd.services.alloy.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "alloy";
    Group = "alloy";
  };

}
