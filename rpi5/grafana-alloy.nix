{
  pkgs,
  ...
}:
{
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "messagebus" ];
  services.alloy = {
    enable = true;
    configPath = pkgs.writeText "simple-alloy-config" ''
      import.git "rules" {  
        repository = "https://github.com/Alper-Celik/grafana-alloy-configs"
        revision   = "main"
        path       = "."
      }  

      rules.rpi5 "rpi5" {}  
    '';
  };
}
