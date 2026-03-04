{
  config,
  lib,
  pkgs,
  trusted-ssh-keys,
  inputs,
  ...
}:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  hardware.enableRedistributableFirmware = true;
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "ent-box";
  networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkDefault true;
  time.timeZone = "Europe/Istanbul";

  hardware.graphics.enable = true;
  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  console = {
    keyMap = "trq";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  documentation.man.generateCaches = false; # needed man completions but takes loong time

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  services.libinput.enable = true;

  programs.fish.enable = true;
  users.users.root = {
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = trusted-ssh-keys;
  };
  users.users.ent-box = {
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

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

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
