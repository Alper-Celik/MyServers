#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

# stop immich before backup
start_immich() {
	systemctl start immich-server.service
}
trap start_immich EXIT
systemctl stop immich-server.service

restic -vv -r /backup-repo/ --insecure-no-password backup --stdin-filename immich.sql --stdin-from-command -- sudo -u immich pg_dump -U immich immich

restic -v -r /backup-repo/ --insecure-no-password backup /var/lib/immich

start_immich

# these files dont change frequently
restic -v -r /backup-repo/ --insecure-no-password backup /var/lib/multimedia/media/photos_from_hdd
