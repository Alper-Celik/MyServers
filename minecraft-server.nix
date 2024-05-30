{ config, pkgs, ... }:
let
  generic-server = pkgs.writeShellApplication {
    name = "minecraft-server";

    runtimeInputs = [ pkgs.jre8 ];

    text = ''
      exec java "$@" -jar /var/lib/minecraft/server.jar nogui
    '';
  };
in
{
  services.minecraft-server = {
    package = generic-server;
    # enable = true;
    eula = true;
    openFirewall = true;
    jvmOpts = "-server -Xms2G -Xmx2G";
  };
}

