{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "rtsx_usb_sdmmc"
    "bcache"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/cfd5ecfc-20cf-466d-9502-61e427c29aa3";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "subvol=@root"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/D7B8-DDD5";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/cfd5ecfc-20cf-466d-9502-61e427c29aa3";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "subvol=@home"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/cfd5ecfc-20cf-466d-9502-61e427c29aa3";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "subvol=@nix"
    ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/1862ad46-04bd-4f46-b7b4-9eae4cab2466"; }
  ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp2s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp3s0.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
