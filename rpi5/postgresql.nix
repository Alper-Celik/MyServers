{
  config,
  pkgs,
  pkgs-stable,
  lib,
  ...
}:
let
  # psycopg 3.3.5 (unstable) turned `_encodings._py_codecs` into a tuple; pgadmin 9.14
  # assigns into it, so it fails at import and its failing build check blocks the whole
  # fleet's deploy. Take psycopg from stable (3.3.4) rather than pinning a version here.
  python3 = pkgs.python3.override {
    packageOverrides = _: prev: {
      psycopg = prev.psycopg.overridePythonAttrs (_: {
        inherit (pkgs-stable.python3Packages.psycopg) version src;
      });
    };
  };
in
{

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 5432 ];
  networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ 5432 ];
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    enableJIT = true;
  };

  services.pgadmin = {
    enable = true;
    package = pkgs.pgadmin4.override { inherit python3; };
    initialEmail = "alper@alper-celik.dev";
    initialPasswordFile = config.sops.secrets.pgadmin-pass.path;
  };
  systemd.services.pgadmin.serviceConfig.TimeoutStartSec = "10min";

  services.caddy.virtualHosts."pgadmin.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString config.services.pgadmin.port}";
  };

}
