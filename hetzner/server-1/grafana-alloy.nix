{
  pkgs,
  ...
}:
{
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [
    "messagebus"

    # for journal see https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/
    "adm"
    "systemd-journal"
  ];

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 12345 ];
  services.alloy = {
    enable = true;
    configPath = pkgs.writeText "simple-alloy-config" ''
      import.git "rules" {  
        repository = "https://github.com/Alper-Celik/grafana-alloy-configs"
        revision   = "main"
        path       = "."
      }  

      rules.hetzner_server_1 "hetzner_server_1" {}  
    '';
  };
}
