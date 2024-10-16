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

    # Instead of using pkgs.nextcloud29Packages.apps or similar,
    # we'll reference the package version specified in services.nextcloud.package
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        bookmarks
        calendar
        contacts
        cookbook
        deck
        mail
        memories
        music
        notes
        previewgenerator
        tasks
        twofactor_webauthn
        onlyoffice
        ;
    };
    extraAppsEnable = true;
    autoUpdateApps.enable = true;

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
