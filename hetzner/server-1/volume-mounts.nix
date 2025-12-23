{ ... }:
{
  fileSystems."/server-1-vol-1" = {
    device = "/dev/disk/by-label/server-1-vol-1";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/var/lib/postgresql" = {
    device = "/dev/disk/by-label/server-1-vol-1";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "noatime"
      "subvol=@postgresql"
    ];
  };

  fileSystems."/var/lib/forgejo" = {
    device = "/dev/disk/by-label/server-1-vol-1";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "noatime"
      "subvol=@forgejo"
    ];
  };
}
