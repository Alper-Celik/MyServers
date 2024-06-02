{ config, pkgs, ... }:
let
  generic-server = pkgs.writeShellApplication {
    name = "minecraft-server";

    runtimeInputs = [ pkgs.jdk17 ];

    text = ''
      exec /var/lib/minecraft/ServerStart.sh
    '';
  };
in
{
  services.minecraft-server = {
    package = generic-server;
    enable = true;
    eula = true;
    openFirewall = true;
    # jvmOpts = "-server -Xms2G -Xmx2G";
    jvmOpts = "";
  };
}

