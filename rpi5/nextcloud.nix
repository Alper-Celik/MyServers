{ pkgs, config, ... }:
{

  environment.systemPackages = with pkgs; [
    restic

    ffmpeg-headless
    exiftool
    nodejs
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
        ;
    };

    caching.redis = true;
    configureRedis = true;

    config = {
      adminpassFile = config.sops.secrets.nextcloud-admin-pass.path;
      dbtype = "pgsql";
    };
    database.createLocally = true;

    package = pkgs.nextcloud33;
    hostName = "nextcloud.lab.alper-celik.dev";
    https = true;

    autoUpdateApps.enable = true;
    appstoreEnable = true;

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

  services.caddy.virtualHosts.${config.services.nextcloud.hostName} = {
    extraConfig = ''
      root ${config.services.nginx.virtualHosts.${config.services.nextcloud.hostName}.root}
      # Rule borrowed from `.htaccess` to handle Microsoft DAV clients
      @mswebdav {
        path /
        header User-Agent DavClnt*
      }
      redir @mswebdav /remote.php/webdav/ temporary
      redir /.well-known/carddav /remote.php/dav/ 301
      redir /.well-known/caldav /remote.php/dav/ 301

      @hidden {
        # Rules borrowed from `.htaccess` to hide certain paths from clients
        path_regexp ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)
        path_regexp ^/(?:\.|autotest|occ|issue|indie|db_|console)

        # Hide metadata files which would otherwise be served as plain files and
        # leak dependency information (composer.json, package.json, core/shipped.json).
        path_regexp ^/(?:composer\.(?:json|lock)|package(?:-lock)?\.json|core/shipped\.json)$
      }
      error @hidden 404


      @static_files {
        file
        path_regexp \.(?:css|js|mjs|svg|gif|ico|jpg|png|webp|wasm|tflite|map|ogg|flac|mp4|webm)$
      }
      @immutable_files {
        file
        path_regexp \.(?:css|js|mjs|svg|gif|ico|jpg|png|webp|wasm|tflite|map|ogg|flac|mp4|webm)$
        query v=*
      }
      header @static_files {
        # HTTP response headers borrowed from Nextcloud `.htaccess`
        Cache-Control                     "public, max-age=15778463"
        Referrer-Policy                   "no-referrer"
        X-Content-Type-Options            "nosniff"
        X-Frame-Options                   "SAMEORIGIN"
        X-Permitted-Cross-Domain-Policies "none"
        X-Robots-Tag                      "noindex, nofollow"
      }
      header @immutable_files Cache-Control "public, max-age=15778463, immutable"

      @font_files {
        file
        path_regexp \.(?:otf|woff2?)$
      }
      header @font_files Cache-Control "public, max-age=604800"

      header {
        # HTTP response headers borrowed from Nextcloud `.htaccess`
        Referrer-Policy                   "no-referrer"
        X-Content-Type-Options            "nosniff"
        X-Frame-Options                   "SAMEORIGIN"
        X-Permitted-Cross-Domain-Policies "none"
        X-Robots-Tag                      "noindex, nofollow"

        # Remove X-Powered-By, which is an information leak
        -X-Powered-By
      }

      php_fastcgi unix/${config.services.phpfpm.pools.nextcloud.socket} {
        root ${config.services.nginx.virtualHosts.${config.services.nextcloud.hostName}.root}
        env front_controller_active true
        env modHeadersAvailable true
      }
      redir /remote* /remote.php{uri} permanent
      try_files {path} {path}/ /index.php{uri}
    '';
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
