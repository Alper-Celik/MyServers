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

  services.caddy.virtualHosts."jellyfin.lab.alper-celik.dev" = {
    extraConfig = ''

        reverse_proxy http://localhost:8096

        ### migrated from nginx config \/
        
        header {
          # Security / XSS Mitigation Headers
          # NOTE: X-Frame-Options may cause issues with the webOS app
          X-Frame-Options "SAMEORIGIN";
          X-Content-Type-Options "nosniff";


          # Permissions policy. May cause issues with some clients
          Permissions-Policy "accelerometer=(), ambient-light-sensor=(), battery=(), bluetooth=(), camera=(), clipboard-read=(), display-capture=(), document-domain=(), encrypted-media=(), gamepad=(), geolocation=(), gyroscope=(), hid=(), idle-detection=(), interest-cohort=(), keyboard-map=(), local-fonts=(), magnetometer=(), microphone=(), payment=(), publickey-credentials-get=(), serial=(), sync-xhr=(), usb=(), xr-spatial-tracking=()" always;

        
        # Content Security Policy
        # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
        # Enforces https content and restricts JS/CSS to origin
        # External Javascript (such as cast_sender.js for Chromecast) must be whitelisted.
        # NOTE: The default CSP headers may cause issues with the webOS app
        Content-Security-Policy "default-src https: data: blob: ; img-src 'self' https://* ; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://www.gstatic.com https://www.youtube.com blob:; worker-src 'self' blob:; connect-src 'self'; object-src 'none'; frame-ancestors 'self'";
      }
    '';
  };
}
