{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
{

  # environment.systemPackages = [ pkgs.rclone ];
  #
  # fileSystems."/mnt/ym-pdf" = {
  #   device = "remote:/Ders pdf'leri";
  #   fsType = "rclone";
  #   options = [
  #     "ro"
  #     "_netdev"
  #     "noauto"
  #     "x-systemd.automount"
  #     "nofail"
  #     "args2env"
  #     "config=${config.sops.secrets.rclone-onedrive-config.path}"
  #     "cache_dir=/var/cache/rclone"
  #
  #     "vfs_cache_max_age=96h0m0s"
  #     "vfs_cache_mode=full"
  #
  #     "nodev"
  #     "nosuid"
  #     "allow_other"
  #   ];
  # };
  #
  # fileSystems."/mnt/my-pdf/app" = {
  #   device = "/persistent/mnt/my-pdf/app";
  #   options = [ "nofail" ];
  #   depends = [
  #     "/mnt/ym-pdf"
  #     # "/persistent"
  #   ];
  #   fsType = "bind";
  # };
  # fileSystems."/mnt/my-pdf/index.php" = {
  #   device = "/persistent/mnt/my-pdf/index.php";
  #   options = [ "nofail" ];
  #   depends = [
  #     "/mnt/ym-pdf"
  #     # "/persistent"
  #   ];
  #   fsType = "bind";
  # };
  #
  # services.nginx.virtualHosts."beta.ym-pdf.alper-celik.dev" = {
  #   enableACME = true;
  #   forceSSL = true;
  #   acmeRoot = null;
  #   expose = true;
  #   root = "/mnt/ym-pdf";
  #   extraConfig = "index index.html index.htm index.php;";
  #   locations."/".extraConfig = "try_files $uri $uri/ /index.php$is_args$args;";
  #   locations."~ ^(.+\\.php)(.*)$" = {
  #     extraConfig = ''
  #       fastcgi_split_path_info ^(.+\.php)(/.+)$;
  #       fastcgi_pass unix:${config.services.phpfpm.pools.ym-pdf-listing.socket};
  #       fastcgi_index index.php;
  #
  #       include ${pkgs.nginx}/conf/fastcgi.conf;
  #     '';
  #   };
  #
  # };
  #
  # services.phpfpm.pools.ym-pdf-listing = {
  #   user = "ym-pdf";
  #   settings = {
  #     "listen.owner" = config.services.nginx.user;
  #     "pm" = "dynamic";
  #     "pm.max_children" = 32;
  #     "pm.max_requests" = 500;
  #     "pm.start_servers" = 2;
  #     "pm.min_spare_servers" = 2;
  #     "pm.max_spare_servers" = 5;
  #     "php_admin_value[error_log]" = "stderr";
  #     "php_admin_flag[log_errors]" = true;
  #     "catch_workers_output" = true;
  #   };
  #   phpEnv."PATH" = lib.makeBinPath [ pkgs.php ];
  # };
  # users.users.ym-pdf = {
  #   isSystemUser = true;
  #   group = "ym-pdf";
  # };
  # users.groups.ym-pdf = { };
}
