#!/usr/bin/env nix
#! nix shell ../#octodns --command bash
octodns-sync --config-file ./production.yaml "$@"
