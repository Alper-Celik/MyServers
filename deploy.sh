#!/usr/bin/env nix
#! nix shell .#deploy-rs --command bash
deploy "$(dirname "$0")" --auto-rollback false --magic-rollback false
