{ inputs, config, ... }:
let
  secrets = inputs.MyServersSecrets;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = "${secrets}/secrets/hetzner/server-1.yaml";
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
    secrets = {
      CLOUDFLARE_API_KEY = { };
      CLOUDFLARE_EMAIL = { };
      tailscale-auth-key-hetzner-server-1 = { };
      GITLAB_RUNNER_AUTOCODE = { };
      MIMIR_S3_ENV_FILE = { };
      LOKI_S3_ENV_FILE = { };
    };
  };
}
