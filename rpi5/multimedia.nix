{ config, ... }:
{

  users = {
    users."media" = {
      isSystemUser = true;
      group = "media";
      uid = 975;
    };
    groups."media" = {
      gid = 969;
    };
  };
  fileSystems."/var/lib/multimedia/media" = {
    fsType = "overlay";
    device = "overlay";
    options = [
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.requires-mounts-for=/var/lib/multimedia"
      "lowerdir=/var/lib/multimedia/lowerdir"
      "upperdir=/var/lib/multimedia/upperdir"
      "workdir=/var/lib/multimedia/.workdir"
    ];
  };
}
