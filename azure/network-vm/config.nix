{
  lib,
  modulesPath,
  trusted-ssh-keys,
  pkgs,
  ...
}:
{
  imports = [
    ./disk.nix
  ];
  users.users.root = {
    openssh.authorizedKeys.keys = trusted-ssh-keys;
    shell = pkgs.fish;
  };
  environment.enableAllTerminfo = true;
  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    fish
  ];

  networking.hostName = "network-vm";
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

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  # Uncomment if you want to enable azure agent (waagent):
  require = [
    (modulesPath + "/virtualisation/azure-agent.nix")
  ];
  virtualisation.azure.agent.enable = true;

  boot = {
    kernelParams = [
      "console=ttyS0"
      "earlyprintk=ttyS0"
      "rootdelay=300"
      "panic=1"
      "boot.panic_on_fail"
    ];
    initrd.kernelModules = [
      "hv_vmbus"
      "hv_netvsc"
      "hv_utils"
      "hv_storvsc"
    ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      timeout = 0;
      grub.configurationLimit = 0;
    };
    growPartition = true;
  };

  networking.useDHCP = true;

  system.stateVersion = "24.05"; # Did you read the comment?

}
