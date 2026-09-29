# Forgejo's state and database into the fleet's shared B2 restic repo.
#
# Shared with ovhcloud-server-1: both hosts push into the same repository (and
# dedupe against each other), so RESTIC_REPOSITORY must stay identical there
# while --host stays distinct — `forget` without --host would prune the other
# host's snapshots too.
RESTIC_REPOSITORY="s3:https://s3.eu-central-003.backblazeb2.com/Backup-shared"
BACKUP_HOST="hetzner-server-1"
export RESTIC_REPOSITORY
export RESTIC_CACHE_DIR="/var/cache/restic/forgejo"

# restic reads AWS_* directly; the unit only has the sops files
AWS_ACCESS_KEY_ID="$(cat "$AWS_ACCESS_KEY_ID_FILE")"
AWS_SECRET_ACCESS_KEY="$(cat "$AWS_SECRET_ACCESS_KEY_FILE")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# first run against the empty bucket creates the repository
restic cat config >/dev/null 2>&1 || restic init

# the other host backs up on its own schedule and prune takes an exclusive lock,
# so wait for it rather than failing the night's backup
restic --retry-lock 30m backup \
  --host "$BACKUP_HOST" --tag forgejo --tag db \
  --stdin-filename forgejo.sql --stdin-from-command -- pg_dump --no-owner forgejo

restic --retry-lock 30m backup \
  --host "$BACKUP_HOST" --tag forgejo \
  --exclude /var/lib/forgejo/log \
  --exclude /var/lib/forgejo/dump \
  /var/lib/forgejo

restic --retry-lock 30m forget \
  --host "$BACKUP_HOST" \
  --keep-daily 7 --keep-weekly 5 --keep-monthly 6 \
  --prune
