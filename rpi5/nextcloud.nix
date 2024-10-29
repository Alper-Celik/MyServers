{ pkgs, config, ... }:
{
  services.nextcloud = {
    enable = true;

    maxUploadSize = "10G";

    config = {
      adminpassFile = config.sops.secrets.nextcloud-admin-pass.path;
      dbtype = "pgsql";
    };
    database.createLocally = true;

    package = pkgs.nextcloud30;
    hostName = "nextcloud.lab.alper-celik.dev";
    https = true;

    autoUpdateApps.enable = true;
    appstoreEnable = true;

    settings = {
      default_phone_region = "TR";
      enabledPreviewProviders = [
        "OC\\Preview\\BMP"
        "OC\\Preview\\GIF"
        "OC\\Preview\\JPEG"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\MP3"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\PNG"
        "OC\\Preview\\TXT"
        "OC\\Preview\\XBitmap"
        "OC\\Preview\\HEIC"
      ];
    };
  };

  services.nginx.virtualHosts.${config.services.nextcloud.hostName} = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
  };
}
