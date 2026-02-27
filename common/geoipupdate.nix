{
  inputs,
  config,
  lib,
  ...
}:
let
  secrets = inputs.MyServersSecrets;
in
{

  config = {

    sops.secrets = {
      geoipupdate_license_key = {
        sopsFile = "${secrets}/secrets/common.yaml";
        format = "yaml";
      };
    };
    services.geoipupdate = {
      enable = true;
      interval = "daily";
      settings = {
        AccountID = 1305508;
        LicenseKey = {
          _secret = config.sops.secrets.geoipupdate_license_key.path;
        };
        EditionIDs = [
          "GeoLite2-ASN"
          "GeoLite2-City"
          "GeoLite2-Country"
        ];
      };
    };
  };
}
