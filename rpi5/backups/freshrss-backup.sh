#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

# stop freshrss before backup
start_freshrss() {
	systemctl start phpfpm-freshrss.service
}
trap start_freshrss EXIT
systemctl stop phpfpm-freshrss.service

restic -vv -r /backup-repo/ --insecure-no-password backup --stdin-filename freshrss.sql --stdin-from-command -- sudo -u freshrss pg_dump -U freshrss freshrss

restic -v -r /backup-repo/ --insecure-no-password backup /var/lib/freshrss

start_freshrss
