{ config, lib, ... }:
let
  cfg = config.services.syncthing;
  syncthing-base = "/var/lib/syncthing";
in
{

  users.users.${cfg.user} = {
    home = config.services.syncthing.dataDir;
    createHome = lib.mkForce false;
    extraGroups = [
      "calibre-web"
      "nextcloud"
    ];
  };

  services.syncthing = {
    enable = true;
    dataDir = syncthing-base + "/data";
    configDir = syncthing-base + "/config";
    settings = {
      gui.insecureSkipHostcheck = true; # there is already nginx proxy that is behind tailscale
    };
    overrideDevices = false;
    overrideFolders = false;
  };

  systemd.tmpfiles.rules =
    let
      acl-generate =
        user-or-group: name: acl:
        "${user-or-group}:${name}:${acl}";
      acl-generate-with-defalut =
        user-or-group: name: acl:
        let
          acl-end = acl-generate user-or-group name acl;
        in
        "${acl-end},default:${acl-end}";
      acl-generate-user-and-group =
        name: acl:
        let
          acl-end = user-group: acl-generate-with-defalut user-group name acl;
        in
        "${acl-end "user"},${acl-end "group"}";
      acl = acl-generate-user-and-group;
    in
    [
      "d ${syncthing-base} 0771 ${cfg.user} ${cfg.group} - -" # let acl'ed users/groups pass through by setting executable bit on other
      "d ${cfg.dataDir} 0771 ${cfg.user} ${cfg.group} - -"

      "d ${cfg.configDir} 0770 ${cfg.user} ${cfg.group} - -"

      "A ${cfg.dataDir} - - - - ${acl "nextcloud" "rwX"}"
      "A ${cfg.dataDir}/Music - - - - ${acl "jellyfin" "rwX"},${acl "navidrome" "rwX"},${acl "nextcloud" "rwX"}"
      "A \"${cfg.dataDir}/Calibre Library\" - - - - ${acl "calibre-web" "rwX"}"

      # SSH access for the ai-agent user on hetzner (see ai-agent.nix).
      # Recursive (A+) so EXISTING files pick up the entry — the service users
      # above predate this user and their defaults never covered it — plus
      # default ACLs so files syncthing creates later inherit it.
      "A+ ${cfg.dataDir}/Music - - - - ${acl "ai-agent" "rwX"}"
    ];

  # Keeps default-ACL masks from clipping named users to read-only: syncthing
  # creates files 0644 by default and the ACL mask is derived from the create
  # mode's group bits. 0002 keeps group bits rw. Group is syncthing's own, so
  # nothing outside the ACL set gains anything. (UMask is a [Service] key —
  # serviceConfig, not unitConfig.)
  systemd.services.syncthing.serviceConfig.UMask = "0002";

  services.caddy.virtualHosts."syncthing-rpi.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://${config.services.syncthing.guiAddress}";
  };

  systemd.services."syncthing-backup" = {
    serviceConfig = {
      PAMName = "sudo";
      ExecStart = "${./backups/syncthing-backup.sh}";
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    startAt = "2:25";
  };

}
