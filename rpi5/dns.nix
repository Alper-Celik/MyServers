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

  # systemd.services."octo-dns-update" = {
  #   enable = true;
  #   wantedBy = [ "network-online.target" ];
  #   script = ''
  #     set -eu
  #     export CLOUDFLARE_TOKEN=$(cat ${config.sops.secrets.CLOUDFLARE_TOKEN-dns.path})
  #     ${fpkgs.octodns}/bin/octodns-sync --config-file "${fpkgs.octodns-config}" --force --doit
  #   '';
  #   serviceConfig = {
  #     Type = "oneshot";
  #     User = config.users.users.octo-dns.name;
  #   };
  #   startAt = "*:0/5";
  #
  # };
  #
  # users.users.octo-dns = {
  #   isSystemUser = true;
  #   group = "octo-dns";
  # };
  # users.groups.octo-dns = { };
  #
  # services.unbound = {
  #   # FIXME: unbound doesnt support ttl noooooo
  #
  #   # enable = true;
  #   settings = {
  #     server = {
  #       interface = [
  #         "127.0.0.1"
  #         "tailscale0"
  #       ];
  #       local-zone = "alper-celik.dev static";
  #       local-data = builtins.map (record: "\"" + (lib.strings.escape [ "\"" ] record) + "\"") (
  #         (lib.strings.splitString "\n" (builtins.readFile "${fpkgs.zoneFiles}/alper-celik.dev"))
  #         ++ [
  #           # "rpi5.devices.alper-celik.dev. IN 300 A 100.104.52.23"
  #         ]
  #       );
  #     };
  #   };
  # };

  # services.bind = {
  #   enable = true;
  #   zones."alper-celik.dev" = {
  #     file = pkgs.writeText "bindcfg" (
  #       (builtins.readFile "${fpkgs.zoneFiles}/alper-celik.dev")
  #       + ''
  #
  #         rpi5.devices.alper-celik.dev. IN 300 A 100.104.52.23
  #       ''
  #     );
  #     # master = false;
  #   };
  # };
}
