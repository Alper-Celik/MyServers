# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let

  personal-ssh-public-keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBZSTiDOsVRhcnOO/foEiy2gp3pJt+62QTFGvVJ0AOX u0_a413@localhost"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKhCFPTP1/JLMCCJttaw88EgBQzPt5fF7EcjXIgDdeuM alper@alper-celik.dev"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIvcX+CPn9rgA6I4MutAQS5Ehybcc5tusPqCvTw8aH0"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDEdpGzo/K4jrtmXtUDlsR8RYWa/Q87plonNjcfMgOPJ"
  ];
  github-ssh-public-key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCRF5cEocxBruwIB7FJsQyCR58DLmNaCgZFyqEnHUvkRb3iudYYnp8b+ApiVPGhPlu+PwzA5kQbKynVN+r/gvjBP2o/wcwvIGSXgy97JRIyD6LwyVjc/fguS9rCCWpU+bt3UPxHIVTHgF9SaMt/4ragM85sKNv+Mq3nNN9J4pHSXfbzTz3+gNyZRorW9bX8+ehIwcOZ0rvYkpvYYq6FExBsORmbNHC8/bsSsQf5riE9Ja4+d8VZQqjB8ix9glwxqOIzfsB77mLT7HZQQXDCRbmkqRT1J421DRIXljXsKtlOEHjV6e2A1gTbS88h3E5/5KqNcMN47paD7EhM3n+1oA5F+0Jw0KkZl+0QogL/c1Gl5UTBdsdDwbAPh1hXvkShBu1lCML7bS4/XKfnRsjwNH4meXVuWwepBTAFvDG/BU+Udmm0D3kHJB9RyEDykzoxv7HWXZIDiTPZkoniUlIcaA2mWRAEK4C6oskdu9G6NTfAc8s3wE1ItKeT3o/4Qkb1cnCyWy7ZVKf6yH0h2KqYCs6O9vcMPHzar2ae4gT1iNBCv6C/1RH4RGVD5uagbF+Z+wQiz2gK6UEBXUHcbWwahqNh/8hnW72dC24ZUYMNjnQqgpvSFWWAWktOpM9MYcwPPCDL8UiQQOEq8orRpSzBfSvqBC/5gSk1SZ52bfROtmQGwQ== github runner";
  trusted-ssh-keys = [
    github-ssh-public-key
  ] ++ personal-ssh-public-keys;
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.raspberry-pi-5
    ./secrets.nix
    ./tailscale.nix
  ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlan0.useDHCP = lib.mkDefault true;

  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "1.1.1.1" ];
  networking.interfaces.end0.ipv4.addresses = [
    {
      address = "192.168.1.200";
      prefixLength = 24;
    }
  ];

  networking.hostName = "rpi5"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Istanbul";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  console = {
    keyMap = "trq";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.enableAllTerminfo = true;
  programs.fish.enable = true;

  users.users.root = {
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = trusted-ssh-keys;
  };
  users.users.rpi5 = {
    shell = pkgs.fish;
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = trusted-ssh-keys;
  };

  environment.systemPackages = with pkgs; [
    vim
    fish
  ];

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

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.05"; # Did you read the comment?

}
