{
  lib,
  modulesPath,
  trusted-ssh-keys,
  pkgs,
  ...
}:
{
  networking.hostName = "ovhcloud-server-1";
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  users.users.root = {
    openssh.authorizedKeys.keys = trusted-ssh-keys;
    shell = pkgs.fish;
  };
  environment.enableAllTerminfo = true;
  programs.fish.enable = true;
  documentation.man.generateCaches = false; # needed man completions but takes loong time

  environment.systemPackages = with pkgs; [
    vim
    fish
  ];

  time.timeZone = "Europe/Istanbul";
  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      # X11Forwarding = true;
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  require = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  system.stateVersion = "24.05"; # Did you read the comment?

  nixpkgs.hostPlatform = "x86_64-linux";
}
