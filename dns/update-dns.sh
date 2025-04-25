#!/usr/bin/env nix
#! nix shell ../#octodns --command bash
cd "$(dirname "$(readlink -f "$0")")"
octodns-sync --config-file ./production.yaml "$@"
