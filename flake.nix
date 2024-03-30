{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, nixpkgs, deploy-rs }: {

    nixosConfigurations.rpi5 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";

      modules = [ ./configuration.nix ];
    };

    deploy.nodes.rpi5 = {

      hostname = "192.168.1.200";
      sshUser = "root";
      remoteBuild = true;

      profiles = {
        system = {
          user = "root";
          path = deploy-rs.lib.aarch64-linux.activate.nixos
            self.nixosConfigurations.rpi5;
        };
      };
    };

    # checks =
    #   builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy)
    #   deploy-rs.lib;
  };
}
