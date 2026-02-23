{
  pkgs,
  ...
}:
{
  services.alloy = {
    enable = true;
    configPath = pkgs.writeText "simple-alloy-config" ''
      import.git "rules" {  
        repository = "https://github.com/Alper-Celik/grafana-alloy-configs"
        revision   = "main"
        path       = "hosts/rpi5.alloy"
      }  

      rules.setup "host" {}  
    '';
  };
}
