{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    deploy-rs.url = "github:serokell/deploy-rs";
    my-blog.url = "github:Alper-Celik/MyBlog";

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    MyServersSecrets = {
      url = "git+ssh://git@github.com/Alper-Celik/MyServersSecrets.git";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      deploy-rs,
      ...
    }:
    {

      nixosConfigurations.rpi5 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          inherit inputs;
        };
        modules = [ ./configuration.nix ];
      };

      deploy.nodes.rpi5 = {

        hostname = "rpi5";
        sshUser = "root";
        remoteBuild = true;

        profiles = {
          system = {
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.rpi5;
          };
        };
      };

      # checks =
      #   builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy)
      #   deploy-rs.lib;
    };
}
