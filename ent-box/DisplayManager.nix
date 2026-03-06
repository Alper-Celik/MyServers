{ config, ... }:
{

  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.displayManager = {
    autoLogin = {
      user = config.users.users.ent-box.name;
      enable = true;
    };
    sddm = {
      enable = true;
      wayland = {
        enable = true;
        compositor = "kwin";
      };
      autoNumlock = true;
    };
  };
}
