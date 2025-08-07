#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

# enable maintenance mode before backup
disable_manitenance() {
	nextcloud-occ maintenance:mode --off
}
trap disable_manitenance EXIT
nextcloud-occ maintenance:mode --on

# backup database
restic -vv -r /backup-repo/ --insecure-no-password backup --stdin-filename nextcloud.sql --stdin-from-command -- sudo -u nextcloud pg_dump -U nextcloud nextcloud

restic -v -r /backup-repo/ --insecure-no-password backup /var/lib/nextcloud

disable_manitenance
