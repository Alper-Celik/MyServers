{ pkgs, config, ... }:
{
  users = {
    groups.jellyfin = {
      gid = 976;
    };
    users.jellyfin = {
      uid = 981;
      isSystemUser = true;
      group = config.users.groups.jellyfin.name;
    };
  };

  systemd.services.${config.virtualisation.oci-containers.containers."jellyfin".serviceName}.after = [
    "var-lib-multimedia-media.mount"
  ];

  virtualisation.oci-containers.containers."jellyfin" = {
    image = "docker.io/jellyfin/jellyfin:latest";
    user = "${builtins.toString config.users.users.jellyfin.uid}:${builtins.toString config.users.groups.jellyfin.gid}";

    ports = [ "8096:8096" ];

    volumes = [
      "/var/lib/jellyfin/config:/config"
      "/var/lib/jellyfin/cache:/cache"

      "/var/lib/syncthing/data/Music:/music"
      "/var/lib/multimedia/media:/media"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };
    autoStart = true;
  };

  services.nginx.virtualHosts."jellyfin.lab.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    extraConfig = ''
        ## The default `client_max_body_size` is 1M, this might not be enough for some posters, etc.
        client_max_body_size 20M;

        # Security / XSS Mitigation Headers
        # NOTE: X-Frame-Options may cause issues with the webOS app
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";


        # Permissions policy. May cause issues with some clients
        add_header Permissions-Policy "accelerometer=(), ambient-light-sensor=(), battery=(), bluetooth=(), camera=(), clipboard-read=(), display-capture=(), document-domain=(), encrypted-media=(), gamepad=(), geolocation=(), gyroscope=(), hid=(), idle-detection=(), interest-cohort=(), keyboard-map=(), local-fonts=(), magnetometer=(), microphone=(), payment=(), publickey-credentials-get=(), serial=(), sync-xhr=(), usb=(), xr-spatial-tracking=()" always;

        
      # Content Security Policy
      # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
      # Enforces https content and restricts JS/CSS to origin
      # External Javascript (such as cast_sender.js for Chromecast) must be whitelisted.
      # NOTE: The default CSP headers may cause issues with the webOS app
      add_header Content-Security-Policy "default-src https: data: blob: ; img-src 'self' https://* ; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://www.gstatic.com https://www.youtube.com blob:; worker-src 'self' blob:; connect-src 'self'; object-src 'none'; frame-ancestors 'self'";
    '';
    locations."/".extraConfig = ''
      # Proxy main Jellyfin traffic
      proxy_pass http://localhost:8096;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Protocol $scheme;
      proxy_set_header X-Forwarded-Host $http_host;

      # Disable buffering when the nginx proxy gets very resource heavy upon streaming
      proxy_buffering off;
    '';
    locations."/socket".extraConfig = ''
      # Proxy Jellyfin Websockets traffic
      proxy_pass http://localhost:8096;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Protocol $scheme;
      proxy_set_header X-Forwarded-Host $http_host;
    '';
  };
}
