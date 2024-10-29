{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    deploy-rs.url = "github:serokell/deploy-rs";
    my-blog.url = "github:Alper-Celik/MyBlog";

    impermanence.url = "github:nix-community/impermanence";
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    MyServersSecrets = {
      url = "git+ssh://git@github.com/Alper-Celik/MyServersSecrets.git";
      flake = false;
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      deploy-rs,
      disko,
      ...
    }:
    let
      personal-ssh-public-keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKhCFPTP1/JLMCCJttaw88EgBQzPt5fF7EcjXIgDdeuM alper@alper-celik.dev"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIvcX+CPn9rgA6I4MutAQS5Ehybcc5tusPqCvTw8aH0"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDEdpGzo/K4jrtmXtUDlsR8RYWa/Q87plonNjcfMgOPJ"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBZSTiDOsVRhcnOO/foEiy2gp3pJt+62QTFGvVJ0AOX u0_a413@localhost" # termux note 10 lite
      ];
      github-ssh-public-key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCRF5cEocxBruwIB7FJsQyCR58DLmNaCgZFyqEnHUvkRb3iudYYnp8b+ApiVPGhPlu+PwzA5kQbKynVN+r/gvjBP2o/wcwvIGSXgy97JRIyD6LwyVjc/fguS9rCCWpU+bt3UPxHIVTHgF9SaMt/4ragM85sKNv+Mq3nNN9J4pHSXfbzTz3+gNyZRorW9bX8+ehIwcOZ0rvYkpvYYq6FExBsORmbNHC8/bsSsQf5riE9Ja4+d8VZQqjB8ix9glwxqOIzfsB77mLT7HZQQXDCRbmkqRT1J421DRIXljXsKtlOEHjV6e2A1gTbS88h3E5/5KqNcMN47paD7EhM3n+1oA5F+0Jw0KkZl+0QogL/c1Gl5UTBdsdDwbAPh1hXvkShBu1lCML7bS4/XKfnRsjwNH4meXVuWwepBTAFvDG/BU+Udmm0D3kHJB9RyEDykzoxv7HWXZIDiTPZkoniUlIcaA2mWRAEK4C6oskdu9G6NTfAc8s3wE1ItKeT3o/4Qkb1cnCyWy7ZVKf6yH0h2KqYCs6O9vcMPHzar2ae4gT1iNBCv6C/1RH4RGVD5uagbF+Z+wQiz2gK6UEBXUHcbWwahqNh/8hnW72dC24ZUYMNjnQqgpvSFWWAWktOpM9MYcwPPCDL8UiQQOEq8orRpSzBfSvqBC/5gSk1SZ52bfROtmQGwQ== github runner";
      trusted-ssh-keys = [
        github-ssh-public-key
      ] ++ personal-ssh-public-keys;

    in
    {

      nixosConfigurations = {
        rpi5 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit
              inputs
              trusted-ssh-keys
              ;
          };
          modules = [ ./rpi5/configuration.nix ];
        };
        azure-network-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit
              inputs
              trusted-ssh-keys
              ;
          };
          modules = [
            inputs.disko.nixosModules.disko
            ./azure/network-vm/config.nix
          ];
        };

      };
      deploy.nodes = {
        rpi5 = {
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

        # network-vm = {
        #   hostname = "network-vm";
        #   sshUser = "root";
        #
        #   profiles = {
        #     system = {
        #       user = "root";
        #       path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.azure-network-vm;
        #     };
        #   };
        #
        # };
      };

      # checks =
      #   builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy)
      #   deploy-rs.lib;
    };
}
