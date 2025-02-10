{ inputs, config, ... }:
let
  secrets = inputs.MyServersSecrets;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  users.groups.restic = { };

  sops = {
    defaultSopsFile = "${secrets}/secrets/rpi5.yaml";
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
    secrets = {
      CLOUDFLARE_API_KEY = { };
      CLOUDFLARE_EMAIL = { };
      # CLOUDFLARE_TOKEN-dns = {
      #   owner = config.users.users.octo-dns.name;
      # };
      tailscale-auth-key = { };
      freshrss-admin-pass = rec {
        owner = config.services.freshrss.user;
        group = owner;
      };

      nextcloud-admin-pass = rec {
        owner = "nextcloud";
        group = owner;
      };

      pgadmin-pass = rec {
        owner = config.systemd.services.pgadmin.serviceConfig.User;
        group = owner;
      };

      "postgres/grafana-pass" = {
        owner = config.systemd.services.grafana.serviceConfig.User;
      };
      "postgres/keycloak-pass" = {
        mode = "444";
      };
      restic-pass = { };
      rclone-onedrive-config = { };
    };

  };
}
