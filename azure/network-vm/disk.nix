{ ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-diskseq/1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "128M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ]; # Override existing partition
                # Subvolumes must set a mountpoint in order to be mounted,
                # unless their parent is mounted
                subvolumes = {
                  # Subvolume name is different from mountpoint
                  "/rootfs" = {
                    mountpoint = "/";
                  };
                  # Subvolume name is the same as the mountpoint
                  "/home" = {
                    mountOptions = [ "compress=zstd" ];
                    mountpoint = "/home";
                  };
                  # Sub(sub)volume doesn't need a mountpoint as its parent is mounted
                  "/home/user" = { };
                  # Parent is not mounted so the mountpoint must be set
                  "/nix" = {
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                    mountpoint = "/nix";
                  };
                  # This subvolume will be created but not mounted
                  "/test" = { };
                  # Subvolume for the swapfile
                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap = {
                      swapfile.size = "20M";
                      swapfile2.size = "20M";
                      swapfile2.path = "rel-path";
                    };
                  };
                };

                mountpoint = "/partition-root";
                swap = {
                  swapfile = {
                    size = "20M";
                  };
                  swapfile1 = {
                    size = "20M";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  #   disko.devices.disk.disk1 = {
  #     type = "disk";
  #     device = "/dev/sda";
  #     content = {
  #       type = "gpt";
  #       partitions = {
  #         boot = {
  #           size = "1M";
  #           type = "EF02";
  #         };
  #         esp = {
  #           name = "ESP";
  #           size = "500M";
  #           type = "EF00";
  #           content = {
  #             type = "filesystem";
  #             format = "vfat";
  #             mountpoint = "/boot";
  #           };
  #         };
  #         root = {
  #           size = "100%";
  #
  #           content = {
  #             type = "btrfs";
  #             extraArgs = [ "-f" ];
  #             subvolumes = {
  #               "/root" = {
  #                 mountpoint = "/";
  #                 mountOptions = [
  #                   "compress=zstd"
  #                   "noatime"
  #                 ];
  #               };
  #               "/home" = {
  #                 mountpoint = "/home";
  #                 mountOptions = [
  #                   "compress=zstd"
  #                   "noatime"
  #                 ];
  #               };
  #               "/nix" = {
  #                 mountpoint = "/nix";
  #                 mountOptions = [
  #                   "compress=zstd"
  #                   "noatime"
  #                 ];
  #               };
  #               "/swap" = {
  #                 mountpoint = "/.swapvol";
  #                 swap.swapfile.size = "2G";
  #               };
  #             };
  #             swap = {
  #               swapfile = {
  #                 size = "2G";
  #               };
  #             };
  #           };
  #         };
  #       };
  #     };
  #   };
  #
}
