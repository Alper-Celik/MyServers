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
      GITLAB_RUNNER_AUTOCODE = { };
      MIMIR_S3_ENV_FILE = { };
      LOKI_S3_ENV_FILE = { };

      # read by the forgejo-backup unit, which runs as that user.
      # Alper adds all three to secrets/hetzner/server-1.yaml.
      b2-restic-shared-keyID.owner = "forgejo";
      b2-restic-shared-applicationKey.owner = "forgejo";
      RESTIC_SHARED_PASSWORD.owner = "forgejo";
    };
  };
}
