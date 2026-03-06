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

      lower-dir = "/var/lib/multimedia/lowerdir";
      upper-dir = "/var/lib/multimedia/upperdir";

      adapt-for-up-low = builtins.foldl' (
        list: item:
        list
        ++ [
          (item lower-dir)
          (item upper-dir)
        ]
      ) [ ];
    in
    adapt-for-up-low [
      (dir: "Z ${dir} 2775 media media - -")

      (dir: "A ${dir} - - - - ${acl "jellyfin" "rwX"},${acl "immich" "rwX"}")
    ];

}
