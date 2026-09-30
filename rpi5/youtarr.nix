{
  config,
  pkgs,
  ...
}:
let
  youtarr = config.virtualisation.oci-containers.containers."youtarr";
  db = config.virtualisation.oci-containers.containers."youtarr-db";

  port = 3087;
  dbName = "youtarr";
  dbPassword = config.sops.placeholder."youtarr-db-pass";
  downloadsDir = "/var/lib/multimedia/media/youtube";
in
{
  users = {
    groups.youtarr = {
      gid = 979;
    };
    users.youtarr = {
      uid = 984;
      isSystemUser = true;
      group = config.users.groups.youtarr.name;
    };
  };

  environment.persistence."/persistent".directories = [
    {
      directory = "/var/lib/youtarr";
      user = config.users.users.youtarr.name;
      group = config.users.groups.youtarr.name;
      mode = "u=rwx,g=,o=";
    }
  ];

  sops.templates."youtarr-db-env" = {
    content = ''
      MYSQL_ROOT_PASSWORD=${dbPassword}
      DB_PASSWORD=${dbPassword}
    '';
    restartUnits = [
      "${youtarr.serviceName}.service"
      "${db.serviceName}.service"
    ];
  };

  virtualisation.oci-containers.containers."youtarr-db" = {
    # upstream bundles mariadb 10.3, which is end of life; 10.11 is the current
    # LTS and still satisfies their "10.3 or newer" requirement
    image = "docker.io/library/mariadb:10.11";
    environment = {
      MYSQL_DATABASE = dbName;
      MYSQL_TCP_PORT = "3321";
      MYSQL_CHARSET = "utf8mb4";
      MYSQL_COLLATION = "utf8mb4_unicode_ci";
    };
    environmentFiles = [ config.sops.templates."youtarr-db-env".path ];
    cmd = [
      "--port=3321"
      "--character-set-server=utf8mb4"
      "--collation-server=utf8mb4_unicode_ci"
      "--innodb-file-per-table=1"
      "--innodb-large-prefix=ON"
    ];
    volumes = [ "/var/lib/youtarr/database:/var/lib/mysql" ];
    labels."io.containers.autoupdate" = "registry";
    autoStart = true;
  };

  virtualisation.oci-containers.containers."youtarr" = {
    image = "docker.io/dialmaster/youtarr:v1.85.0";
    user = "${toString config.users.users.youtarr.uid}:${toString config.users.groups.youtarr.gid}";

    dependsOn = [ "youtarr-db" ];
    ports = [ "127.0.0.1:${toString port}:3011" ];
    environment = {
      IN_DOCKER_CONTAINER = "1";
      TZ = config.time.timeZone;
      DB_HOST = "youtarr-db";
      DB_PORT = "3321";
      DB_USER = "root";
      DB_NAME = dbName;
      # safe only because the caddy vhost is tailnet/private-range only, which is
      # the documented use case for turning this off (docs/AUTHENTICATION.md)
      AUTH_ENABLED = "false";
      TRUST_PROXY = "1";
      LOG_LEVEL = "info";
      YOUTUBE_OUTPUT_DIR = downloadsDir;
    };
    environmentFiles = [ config.sops.templates."youtarr-db-env".path ];
    volumes = [
      "${downloadsDir}:/usr/src/app/data"
      "/var/lib/youtarr/config:/app/config"
      "/var/lib/youtarr/jobs:/app/jobs"
      "/var/lib/youtarr/server-images:/app/server/images"
    ];
    labels."io.containers.autoupdate" = "registry";
    autoStart = true;
  };

  systemd.services."youtarr-downloads-dir" = {
    description = "create the Youtarr download directory in the media overlay";
    after = [ "var-lib-multimedia-media.mount" ];
    requiredBy = [ "${youtarr.serviceName}.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -o ${config.users.users.youtarr.name} -g ${config.users.groups."media".name} -m 2775 ${downloadsDir}
    '';
  };

  systemd.services.${youtarr.serviceName}.after = [ "var-lib-multimedia-media.mount" ];

  services.caddy.virtualHosts."youtarr.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString port}";
  };
}
