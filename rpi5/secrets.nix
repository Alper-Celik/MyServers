{ inputs, ... }:
let
  secrets = inputs.MyServersSecrets;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

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
      tailscale-auth-key = { };
      nextcloud-admin-pass = rec {
        owner = "nextcloud";
        group = owner;
      };
    };

  };
}