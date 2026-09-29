{ inputs, ... }:
let
  secrets = inputs.MyServersSecrets;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];
  sops = {
    defaultSopsFile = "${secrets}/secrets/ovhcloud/server-1.yaml";
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };

    # read by the postgres-backup unit, which runs as that user.
    # Alper adds all three to secrets/ovhcloud/server-1.yaml.
    secrets = {
      b2-restic-shared-keyID.owner = "postgres";
      b2-restic-shared-applicationKey.owner = "postgres";
      RESTIC_SHARED_PASSWORD.owner = "postgres";
    };
  };

}
