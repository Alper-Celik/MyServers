{ pkgs, config, ... }:
{

  environment.systemPackages = with pkgs; [
    restic

    ffmpeg-headless
    exiftool
    nodePackages.nodejs
    python3
    gnumake
    gcc
  ];

  services.nextcloud = {
    enable = true;
    phpExtraExtensions = all: [
      all.pdlib
      all.bz2
    ];
    maxUploadSize = "10G";
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        contacts
        calendar
        tasks
        deck
        gpoddersync
        groupfolders
        twofactor_webauthn
        previewgenerator
        recognize
        ;
    };
    extraAppsEnable = false;

    caching.redis = true;
    configureRedis = true;

    config = {
      adminpassFile = config.sops.secrets.nextcloud-admin-pass.path;
      dbtype = "pgsql";
    };
    database.createLocally = true;

    package = pkgs.nextcloud31;
    hostName = "nextcloud.lab.alper-celik.dev";
    https = true;

    autoUpdateApps.enable = false;
    appstoreEnable = false;

    settings = {
      "memories.exiftool" = "/run/current-system/sw/bin/exiftool";
      "social_login_auto_redirect" = false;
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

  services.collabora-online = {
    enable = true;
    settings = {
      # ssl.termination = true;
      # ssl.enable = false;
      net = {
        proto = "ipv4";
        listen = "loopback";
      };

      storage.wopi = {
        host = "nextcloud.lab.alper-celik.dev";
      };
    };
  };

  services.nginx.virtualHosts."collabora-online.lab.alper-celik.dev" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;

    extraConfig = ''
      # static files
      location ^~ /browser {
        proxy_pass https://127.0.0.1:9980;
        proxy_set_header Host $host;
      }

      # WOPI discovery URL
      location ^~ /hosting/discovery {
        proxy_pass https://127.0.0.1:9980;
        proxy_set_header Host $host;
      }

      # Capabilities
      location ^~ /hosting/capabilities {
        proxy_pass https://127.0.0.1:9980;
        proxy_set_header Host $host;
      }

      # main websocket
      location ~ ^/cool/(.*)/ws$ {
        proxy_pass https://127.0.0.1:9980;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 36000s;
      }

      # download, presentation and image upload
      location ~ ^/(c|l)ool {
        proxy_pass https://127.0.0.1:9980;
        proxy_set_header Host $host;
      }

      # Admin Console websocket
      location ^~ /cool/adminws {
        proxy_pass https://127.0.0.1:9980;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 36000s;
      }
    '';
  };

  systemd.services."nextcloud-backup" = {
    serviceConfig = {
      PAMName = "sudo";
      ExecStart = "${./backups/nextcloud-backup.sh}";
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    startAt = "2:20";
  };

}
