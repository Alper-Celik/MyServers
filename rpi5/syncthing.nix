{ config, ... }:
{

  users.users.${config.services.syncthing.user}.home = config.services.syncthing.dataDir;
  services = {
    syncthing = {
      enable = true;
      settings = {
        gui.insecureSkipHostcheck = true; # there is already nginx proxy that is behind tailscale
      };
      overrideDevices = false;
      overrideFolders = false;
    };

    nginx.virtualHosts."syncthing-rpi.lab.alper-celik.dev" = {
      forceSSL = true;
      enableACME = true;
      acmeRoot = null;
      locations."/" = {
        proxyPass = "http://${config.services.syncthing.guiAddress}";
      };
    };
  };
}
