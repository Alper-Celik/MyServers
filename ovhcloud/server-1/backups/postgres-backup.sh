# The cluster's databases into the fleet's shared B2 restic repo.
#
# Shared with hetzner-server-1: both hosts push into the same repository, so
# RESTIC_REPOSITORY must stay identical there while --host stays distinct —
# `forget` without --host would prune the other host's snapshots too.
RESTIC_REPOSITORY="s3:https://s3.eu-central-003.backblazeb2.com/Backup-shared"
BACKUP_HOST="ovhcloud-server-1"
export RESTIC_REPOSITORY
export RESTIC_CACHE_DIR="/var/cache/restic/postgres"

# restic reads AWS_* directly; the unit only has the sops files
AWS_ACCESS_KEY_ID="$(cat "$AWS_ACCESS_KEY_ID_FILE")"
AWS_SECRET_ACCESS_KEY="$(cat "$AWS_SECRET_ACCESS_KEY_FILE")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# first run against the empty bucket creates the repository
restic cat config >/dev/null 2>&1 || restic init

# whole cluster (keycloak, hindsight, …) so a new database is covered without
# editing this script; runs as postgres, so the socket peer-auth needs no password
restic --retry-lock 30m backup \
  --host "$BACKUP_HOST" --tag postgres \
  --stdin-filename pg_dumpall.sql --stdin-from-command -- pg_dumpall --clean

restic --retry-lock 30m forget \
  --host "$BACKUP_HOST" \
  --keep-daily 7 --keep-weekly 5 --keep-monthly 6 \
  --prune
