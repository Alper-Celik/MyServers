{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:

let
  fpkgs = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
in
{

  systemd.services."octo-dns-update" = {
    enable = true;
    wantedBy = [ "network-online.target" ];
    script = ''
      set -eu
      export CLOUDFLARE_TOKEN=$(cat ${config.sops.secrets.CLOUDFLARE_TOKEN-dns.path})
      ${fpkgs.octodns}/bin/octodns-sync --config-file "${../dns/ddns-rpi5.yaml}" --force --doit 
    '';
    serviceConfig = {
      Type = "oneshot";
      User = config.users.users.octo-dns.name;
    };
    startAt = "*:0/5";

  };

  users.users.octo-dns = {
    isSystemUser = true;
    group = "octo-dns";
  };
  users.groups.octo-dns = { };
}
