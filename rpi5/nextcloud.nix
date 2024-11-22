{ pkgs, config, ... }:
{

  environment.systemPackages = with pkgs; [
    ffmpeg-headless
    exiftool
    nodePackages.nodejs
    python3
    gnumake
    gcc
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
      "social_login_auto_redirect" = true;
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
    expose = true;
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
}
