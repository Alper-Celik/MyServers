{ pkgs, config, ... }:
{

  environment.systemPackages = with pkgs; [
    ffmpeg-headless
    exiftool
    nodePackages.nodejs
  ];

  services.nextcloud = {
    enable = true;

    maxUploadSize = "10G";

    caching.redis = true;
    configureRedis = true;

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
      "memories.exiftool" = "/run/current-system/sw/bin/exiftool";
      maintenance_window_start = "0"; # 3 am in utc+3
      default_phone_region = "TR";
      enabledPreviewProviders = [
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\MP3"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\XBitmap"
        "OC\\Preview\\TXT"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\Krita"

        "OC\\Preview\\Image"
        "OC\\Preview\\HEIC"
        "OC\\Preview\\TIFF"
        "OC\\Preview\\Movie"
      ];
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = 20;
    };
  };

  services.nginx.virtualHosts.${config.services.nextcloud.hostName} = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
  };
}
