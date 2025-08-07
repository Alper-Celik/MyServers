#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

export AWS_ACCESS_KEY_ID=$(cat "$AWS_ACCESS_KEY_ID_FILE")
export AWS_SECRET_ACCESS_KEY=$(cat "$AWS_SECRET_ACCESS_KEY_FILE")

restic -v -r s3:https://s3.eu-central-003.backblazeb2.com/Backup-rpi5 copy --from-repo /backup-repo/ --from-insecure-no-password --limit-upload 1220 --limit-download 6103
