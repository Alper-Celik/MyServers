#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

# stop freshrss before backup
start_vaultwarden() {
	systemctl start vaultwarden.service
}
trap start_vaultwarden EXIT
systemctl stop vaultwarden.service

restic -vv -r /backup-repo/ --insecure-no-password backup --stdin-filename vaultwarden.sql --stdin-from-command -- sudo -u vaultwarden pg_dump -U vaultwarden vaultwarden

restic -v -r /backup-repo/ --insecure-no-password backup /var/lib/bitwarden_rs

start_vaultwarden
