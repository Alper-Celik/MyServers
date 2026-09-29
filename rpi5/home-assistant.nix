{ postgresSocketDir, ... }:
{
  virtualisation.oci-containers.containers."home-assistant" = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    volumes = [
      "/var/lib/home-assistant:/config"
      "/etc/localtime:/etc/localtime:ro"
      # persistent socket dir (common/postgres-sockets.nix), mounted where the
      # recorder's config expects it; /run/postgresql itself goes stale on a
      # postgres restart
      "${postgresSocketDir}:/run/postgresql"
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

  services.caddy.virtualHosts."home.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://[::1]:8123";
  };
}
