{ ... }:
{
  virtualisation.oci-containers.containers."home-assistant" = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    volumes = [
      "/var/lib/home-assistant:/config"
      "/etc/localtime:/etc/localtime:ro"
      "/run/postgresql/:/run/postgresql/"
      "/run/dbus:/run/dbus:ro"
    ];
    environment = {
      # DISABLE_JEMALLOC = "true"; # enable it if using bigger than 4kb page sizes
    };
    extraOptions = [
      "--network=host"
      "--privileged"
    ];
    labels = {
      "io.containers.autoupdate" = "registry"; # thanks to https://indieweb.social/@MediocreWightMan/113595644096501287
    };
    autoStart = true;
  };

  services.nginx = {
    virtualHosts."home.lab.alper-celik.dev" = {
      forceSSL = true;
      enableACME = true;
      acmeRoot = null;
      locations."/" = {
        proxyPass = "http://[::1]:8123";
        proxyWebsockets = true;
      };
    };
  };
}
