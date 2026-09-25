{
  lib,
  modulesPath,
  trusted-ssh-keys,
  pkgs,
  ...
}:
{
  users.users.root = {
    openssh.authorizedKeys.keys = trusted-ssh-keys;
    shell = pkgs.fish;
  };
  environment.enableAllTerminfo = true;
  programs.fish.enable = true;
  documentation.man.generateCaches = false; # needed man completions but takes loong time

  # Run generic (non-NixOS) ELF binaries: uv-managed CPythons, npm packages with
  # prebuilt native addons, pip manylinux wheels, release tarballs. Without this,
  # the default environment.stub-ld interpreter at /lib/ld-linux-aarch64.so.1 only
  # prints "NixOS cannot run dynamically linked executables" and they exit 127.
  # nix-ld replaces it and provides the usual library set (glibc, libstdc++, zlib,
  # openssl, curl, libxml2, systemd, …); extend it with programs.nix-ld.libraries.
  programs.nix-ld.enable = true;

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

  nixpkgs.hostPlatform = "aarch64-linux";
}
