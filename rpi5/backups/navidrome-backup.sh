#!/usr/bin/env bash
set -euo pipefail

restic -v -r /backup-repo/ --insecure-no-password backup /var/lib/navidrome/backups
