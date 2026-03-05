#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

# stop immich before backup
start_syncthing() {
	systemctl start syncthing.service
	systemctl start podman-calibre-web-automated.service
}
trap start_syncthing EXIT
systemctl stop syncthing.service
systemctl stop podman-calibre-web-automated.service

restic -v -r /backup-repo/ --insecure-no-password backup /var/lib/syncthing

start_syncthing
