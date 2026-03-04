{ inputs, ... }:
let
  secrets = inputs.MyServersSecrets;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  users.groups.restic = { };

  sops = {
    defaultSopsFile = "${secrets}/secrets/ent-box.yaml";
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
  };
}
