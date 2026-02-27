{
  lib,
  config,
  pkgs,
  ...
}:
{
  options = {
    services.nginx.x-enable-geoip = lib.mkOption {
      type = lib.types.bool;
      default = true;

      description = ''
        whether to setup geoip2 for nginx
      '';
    };
  };
  config = lib.mkIf config.services.nginx.x-enable-geoip {
    services.nginx = {
      additionalModules = with pkgs.nginxModules; [
        geoip2
      ];

      appendHttpConfig = ''
        geoip2 /var/lib/GeoIP/GeoLite2-Country.mmdb {
            auto_reload 5m;
            $geoip2_data_country_code default=XX country iso_code;
            $geoip2_data_country_name country names en;
        }

        geoip2 /var/lib/GeoIP/GeoLite2-City.mmdb {
            auto_reload 5m;
            $geoip2_data_city_name   city names en;
            $geoip2_data_latitude    location latitude;
            $geoip2_data_longitude   location longitude;
            $geoip2_data_accuracy_radius location accuracy_radius;
        } '';
    };
  };
}
