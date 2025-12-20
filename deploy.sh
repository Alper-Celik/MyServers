#!/usr/bin/env nix
#! nix shell .#deploy-rs --command bash
deploy "$(dirname "$0")" --auto-rollback false --magic-rollback false -- --accept-flake-config --option substituters "https://nixos-raspberrypi.cachix.org" --option trusted-public-keys "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=" -L
