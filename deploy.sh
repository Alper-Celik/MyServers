#!/usr/bin/env nix
#! nix shell .#deploy-rs --command bash
# Ai generated
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
remote_store="${REMOTE_STORE:-ssh-ng://eu.nixbuild.net}"
nodes=(ovhcloud-server-1 hetzner-server-1 rpi5)
nix_args=(--extra-experimental-features "nix-command flakes")

# Build each profile in the nixbuild.net remote store, then copy the resulting
# closure straight to the target. This plants the already-built closure (kernel
# included) on the host, so the remote build deploy-rs performs below finds the
# output already valid and never compiles anything on the target.
#
# Hosts that are unreachable, or that fail to receive their closure, are skipped
# with a warning so the remaining hosts still get deployed.
deploy_nodes=()
for node in "${nodes[@]}"; do
  meta="$(nix "${nix_args[@]}" eval --raw "$repo#deploy.nodes.$node" \
    --apply 'n: "${n.hostname} ${n.sshUser}"')"
  read -r host ssh_user <<<"$meta"

  echo "==> checking $node at $ssh_user@$host"
  if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$ssh_user@$host" true; then
    echo "==> WARNING: $node ($ssh_user@$host) is unreachable, skipping" >&2
    continue
  fi

  echo "==> building $node for $host in $remote_store"
  if ! closure="$(
    nix "${nix_args[@]}" build \
      --eval-store auto \
      --builders "" \
      --max-jobs 2 \
      --store "$remote_store" \
      --no-link \
      --print-out-paths \
      "$repo#deploy.nodes.$node.profiles.system.path" | tail -n1
  )"; then
    echo "==> WARNING: failed to build $node in $remote_store, skipping" >&2
    continue
  fi

  echo "==> copying $closure to $ssh_user@$host"
  if ! nix "${nix_args[@]}" copy \
    --from "$remote_store" \
    --to "ssh://$ssh_user@$host" \
    --no-check-sigs \
    -s \
    "$closure"; then
    # nixbuild.net documents that direct copies from a remote store can be
    # inconsistent; fall back to staging the closure locally first.
    echo "==> direct copy failed, retrying via local store"
    if ! {
      nix "${nix_args[@]}" copy --from "$remote_store" --no-check-sigs "$closure" &&
        nix "${nix_args[@]}" copy --to "ssh://$ssh_user@$host" --no-check-sigs -s "$closure"
    }; then
      echo "==> WARNING: failed to copy $node to $ssh_user@$host, skipping" >&2
      continue
    fi
  fi

  deploy_nodes+=("$node")
done

if [ ${#deploy_nodes[@]} -eq 0 ]; then
  echo "==> ERROR: no hosts were reachable and deployable" >&2
  exit 1
fi

targets=()
for node in "${deploy_nodes[@]}"; do
  targets+=("$repo#$node")
done

exec deploy --targets "${targets[@]}" --auto-rollback false --magic-rollback false --skip-checks "$@" -- --accept-flake-config --extra-experimental-features flakes -L
