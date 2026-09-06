{
  config,
  lib,
  ...
}:
let
  openwebui-port = 8368;
  uid = 850;
  gid = 851;
in
{
  sops.secrets.OPENWEBUI_SECRET_KEY = {
    owner = config.users.users.openwebui.name;
    group = config.users.groups.openwebui.name;
  };
  users = {
    groups.openwebui.gid = gid;
    users.openwebui = {
      uid = uid;
      isSystemUser = true;
      group = config.users.groups.openwebui.name;
    };
  };
  virtualisation.oci-containers.containers."openwebui" = {
    image = "ghcr.io/open-webui/open-webui:main";
    user = "${toString uid}:${toString gid}";
    ports = [ "${toString openwebui-port}:8080" ];
    volumes = [
      "/var/lib/openwebui:/app/backend/data"
    ];
    environmentFiles = [ config.sops.secrets.OPENWEBUI_SECRET_KEY.path ];
  };
  services.caddy.virtualHosts."llm.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://localhost:${toString openwebui-port}";
  };
}
