# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  inputs,
  trusted-ssh-keys,
  ...
}:
{

  virtualisation = {
    oci-containers = {
      backend = "podman";
    };
    podman = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };
  systemd.enableEmergencyMode = false; # recommendation from https://schreibt.jetzt/@linus/111962725769108997

  imports = [
    # Include the results of the hardware scan.
    inputs.impermanence.nixosModules.impermanence
    inputs.nixos-hardware.nixosModules.raspberry-pi-5
  ];

  hardware.graphics.enable = true;
  environment.persistence."/persistent" = {
    enable = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      # {
      #   directory = "/etc/ssh";
      #   user = "root";
      #   group = "root";
      #   mode = "u=rw,g=,o=";
      # }
    ];
    files = [
      # "/etc/machine-id" #TODO: fix this before enabling proper impermanence
      {
        file = "/var/keys/secret_file";
        parentDirectory = {
          mode = "u=rwx,g=,o=";
        };
      }
    ];

  };

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlan0.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;

  ## not at home anymore soo
  # networking.defaultGateway = "192.168.1.1";
  # networking.nameservers = [ "1.1.1.1" ];
  # networking.interfaces.end0.ipv4.addresses = [
  #   {
  #     address = "192.168.1.200";
  #     prefixLength = 24;
  #   }
  # ];
  #
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

  documentation.man.generateCaches = false; # needed man completions but takes loong time
  # environment.enableAllTerminfo = true;
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
    tmux
    waypipe
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    ports = [
      22
      110 # pop3 port hopefully our universitsy doesnt block it
    ];
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
