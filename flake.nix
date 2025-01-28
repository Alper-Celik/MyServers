{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
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

    nixos-dns = {
      url = "github:Janik-Haag/nixos-dns";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    octodns-ddns-src = {
      url = "github:octodns/octodns-ddns";
      flake = false;
    };
    octodns-cloudflare-src = {
      url = "github:octodns/octodns-cloudflare";
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
      nixos-dns,
      ...
    }:
    let

      dnsConfig = {
        inherit (self) nixosConfigurations;
        extraConfig = import ./dns.nix;
      };

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            self-pkgs = self.packages.${system};
            inherit (self) system;
            pkgs = import nixpkgs {
              inherit # overlays
                system
                ;
            };
          }
        );

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

      all-file =
        dir:
        builtins.map (file: (builtins.toString dir) + "/" + file) (
          builtins.attrNames (builtins.readDir dir)
        );
    in
    {

      nixosConfigurations = {
        hetzner-server-1 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit
              inputs
              trusted-ssh-keys
              ;
          };
          modules = all-file ./hetzner/server-1 ++ [
            nixos-dns.nixosModules.dns
            inputs.disko.nixosModules.disko
          ];
        };

        rpi5 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit
              inputs
              trusted-ssh-keys
              ;
          };
          modules = all-file ./rpi5 ++ [ nixos-dns.nixosModules.dns ];
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
            nixos-dns.nixosModules.dns
            ./azure/network-vm/config.nix
          ];
        };

      };

      deploy.nodes = {
        rpi5 = {
          hostname = "rpi5.devices.alper-celik.dev";
          sshUser = "root";
          remoteBuild = true;

          profiles = {
            system = {
              user = "root";
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.rpi5;
            };
          };
        };
        hetzner-server-1 = {
          hostname = "hetzner-server-1.devices.alper-celik.dev";
          sshUser = "root";
          remoteBuild = true;

          profiles = {
            system = {
              user = "root";
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.hetzner-server-1;
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

      packages = forEachSupportedSystem (
        { pkgs, self-pkgs, ... }:
        let
          generate = nixos-dns.utils.generate pkgs;
        in
        {
          octodns =
            with pkgs;
            (octodns.withProviders (ps: [
              self-pkgs.octodns-cloudflare
              self-pkgs.octodns-ddns
              octodns-providers.bind
            ]));

          octodns-cloudflare = pkgs.python3Packages.callPackage ./pkgs/octodns-cloudflare.nix {
            src = inputs.octodns-cloudflare-src;
          };

          octodns-ddns = pkgs.python3Packages.callPackage ./pkgs/octodns-ddns.nix {
            src = inputs.octodns-ddns-src;
          };
          zoneFiles = generate.zoneFiles dnsConfig;
          octodns-config = generate.octodnsConfig {
            inherit dnsConfig;
            config = {
              processors.only-these = {
                class = "octodns.processor.filter.NameAllowlistFilter";
                allowlist = [
                  "/lab/"
                  "blog"
                  "/ym-pdf/"
                  "/fileshare/"
                  "/devices/"
                  "/tailnet/"
                ];
              };

              providers = {
                config.check_origin = false;
                cloudflare = {
                  class = "octodns_cloudflare.CloudflareProvider";
                  token = "env/CLOUDFLARE_TOKEN";
                };
                "rpi5.devices" = {
                  class = "octodns_ddns.DdnsSource";
                  types = [ "A" ];
                };

              };
            };
            zones = {
              "alper-celik.dev." = {
                sources = [
                  "config"
                  "rpi5.devices"
                ];
                processors = [ "only-these" ];
                targets = [ "cloudflare" ];
              };
            };
          };
        }
      );

      devShells = forEachSupportedSystem (
        {
          pkgs,
          system,
          self-pkgs,
          ...
        }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              yq
              self-pkgs.octodns
            ];
          };
        }
      );

    };
}
