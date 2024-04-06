{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    my-blog.url = "github:Alper-Celik/MyBlog";
  };

  outputs = inputs@{ self, nixpkgs, deploy-rs, ... }: {

    nixosConfigurations.rpi5 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs; };
      modules = [ ./configuration.nix ];
    };

    deploy.nodes.rpi5 = {

      hostname = "rpi5.alper-celik.dev";
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
