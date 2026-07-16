{ config, ... }:
let
  port = config.virtualisation.oci-containers.containers."koinsight".environment.PORT;
in
{
  users = {
    groups.koinsight = {
      gid = 978;
    };
    users.koinsight = {
      uid = 983;
      isSystemUser = true;
      group = config.users.groups.koinsight.name;
    };
  };

  virtualisation.oci-containers.containers."koinsight" = {
    image = "ghcr.io/georgesg/koinsight:latest";
    user = "${builtins.toString config.users.users.koinsight.uid}:${builtins.toString config.users.groups.jellyfin.gid}";

    ports = [ "${port}:${port}" ];
    environment = {
      PORT = "3078";
      MAX_FILE_SIZE_MB = "1024";
    };

    volumes = [
      "/var/lib/koinsight:/app/data"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };
    autoStart = true;
  };
  services.caddy.virtualHosts."koinsight.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${port}";
  };

}
