{ config, ... }:
let
  cwa-port = 8083;
in
{

  users = {
    groups.calibre-web = {
      gid = 962;
    };
    users.calibre-web = {
      isSystemUser = true;
      uid = 972;
      group = config.users.groups.calibre-web.name;
    };
  };

  virtualisation.oci-containers.containers."calibre-web-automated" = {
    image = "docker.io/crocodilestick/calibre-web-automated:latest";
    environment = {
      PUID = builtins.toString config.users.users.calibre-web.uid;
      PGID = builtins.toString config.users.groups.calibre-web.gid;
      TZ = config.time.timeZone;
    };
    volumes = [
      "/var/lib/calibre-web/:/config"
      "/var/lib/syncthing/data/Calibre Library:/calibre-library"
    ];
    ports = [ "8083:8083" ];
    labels = {
      "io.containers.autoupdate" = "registry"; # thanks to https://indieweb.social/@MediocreWightMan/113595644096501287
    };
    autoStart = true;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cwa-port ];
}
