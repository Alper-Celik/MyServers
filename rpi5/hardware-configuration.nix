{
  config,
  inputs,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [
      "subvol=root"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos-nvme";
    fsType = "btrfs";
    options = [
      "subvol=@nix"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/persistent" = {
    neededForBoot = true;
    device = "/dev/disk/by-label/nixos-nvme";
    fsType = "btrfs";
    options = [
      "subvol=@persistent"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/persistent-important" = {
    neededForBoot = true;
    device = "/dev/disk/by-label/nixos-nvme";
    fsType = "btrfs";
    options = [
      "subvol=@persistent-important"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };

  zramSwap = {
    enable = true;
    memoryPercent = 60;
  };
  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlan0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
