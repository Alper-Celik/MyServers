#!/usr/bin/env nix
#! nix shell .#deploy-rs --command bash
# Ai generated
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
remote_store="${REMOTE_STORE:-ssh-ng://eu.nixbuild.net}"
nodes=(ovhcloud-server-1 hetzner-server-1 rpi5)
nix_args=(--extra-experimental-features "nix-command flakes")
ssh_opts=(-o ConnectTimeout=10 -o BatchMode=yes)

# Pinned nixbuild.net host key (same one nixbuild-action uses).
nb_host="${remote_store#ssh-ng://}"
nb_host_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM"
remote_dir="/run/deploy-nixbuild"

# Pull the closure directly on the target from nixbuild.net using the token for
# this run only. nixbuild -> host traffic then never touches the runner (no
# download-then-upload hop) and every host pulls at its own speed. The token is
# written into a 0600 ssh config on the target (tmpfs) and removed afterwards.
#
# The remote login shell may be fish, so every command is run explicitly through
# bash instead of relying on the target's shell.
#
# Returns non-zero if the target could not pull, so the caller can fall back to
# copying through this runner.
pull_on_host() {
  local ssh_user="$1" host="$2" closure="$3"
  local tmpdir conf known tokf rc=0 token
  tmpdir="$(mktemp -d)"
  conf="$tmpdir/ssh_config"
  known="$tmpdir/known_hosts"
  tokf="$tmpdir/token"
  token="$(printf '%s' "$NIXBUILDNET_TOKEN" | tr -d '\r\n')"

  printf '%s %s\n' "$nb_host" "$nb_host_key" > "$known"
  printf '%s' "$token" > "$tokf"
  {
    printf 'Host %s\n' "$nb_host"
    printf '  HostName %s\n' "$nb_host"
    printf '  User authtoken\n'
    printf '  PreferredAuthentications none\n'
    printf '  PubkeyAcceptedKeyTypes ssh-ed25519\n'
    printf '  StrictHostKeyChecking yes\n'
    printf '  UserKnownHostsFile %s/known_hosts\n' "$remote_dir"
    printf '  ControlPath none\n'
    printf '  ServerAliveInterval 60\n'
    printf '  IPQoS throughput\n'
    printf '  SetEnv token=%s\n' "$token"
    printf '  SendEnv NIXBUILDNET_TOKEN\n'
  } > "$conf"

  # ssh joins its arguments with spaces and the remote shell re-parses the
  # result, so each remote command is passed as one pre-quoted argument.
  if ssh "${ssh_opts[@]}" "$ssh_user@$host" "bash -s -- '$remote_dir'" <<'SETUP'
set -euo pipefail
umask 077
rm -rf "$1"
mkdir -p "$1"
SETUP
  then
    ssh "${ssh_opts[@]}" "$ssh_user@$host" \
      "bash -c 'umask 077; cat > \"\$1\"' _ '$remote_dir/known_hosts'" < "$known" || rc=1
    ssh "${ssh_opts[@]}" "$ssh_user@$host" \
      "bash -c 'umask 077; cat > \"\$1\"' _ '$remote_dir/ssh_config'" < "$conf" || rc=1
    ssh "${ssh_opts[@]}" "$ssh_user@$host" \
      "bash -c 'umask 077; cat > \"\$1\"' _ '$remote_dir/token'" < "$tokf" || rc=1

    if [ "$rc" -eq 0 ]; then
      echo "==> $host: pulling $closure from ssh://$nb_host on the host" >&2
      ssh "${ssh_opts[@]}" "$ssh_user@$host" \
        "bash -s -- '$remote_dir' 'ssh://$nb_host' '$closure'" <<'PULL' || rc=1
set -euo pipefail
remote_dir="$1"; pull_store="$2"; closure="$3"
nixbin=""
for c in /run/current-system/sw/bin/nix /nix/var/nix/profiles/default/bin/nix; do
  [ -x "$c" ] && nixbin="$c" && break
done
[ -n "$nixbin" ] || nixbin=nix
NIXBUILDNET_TOKEN="$(cat "$remote_dir/token")" \
  NIX_SSHOPTS="-F $remote_dir/ssh_config" \
  "$nixbin" --extra-experimental-features nix-command \
  copy --from "$pull_store" --no-check-sigs "$closure"
PULL
    fi

    ssh "${ssh_opts[@]}" "$ssh_user@$host" \
      "bash -c 'rm -rf \"\$1\"' _ '$remote_dir'" || true
  else
    rc=1
  fi

  rm -rf "$tmpdir"
  return $rc
}

# 1) Resolve every reachable host's closure path. The closures are already built
#    in nixbuild.net by the workflow's build/check step, so this only evaluates
#    the flake (no build). Hosts that are unreachable are skipped.
declare -A node_host node_ssh_user node_closure
deploy_nodes=()

for node in "${nodes[@]}"; do
  meta="$(nix "${nix_args[@]}" eval --raw "$repo#deploy.nodes.$node" \
    --apply 'n: "${n.hostname} ${n.sshUser}"')"
  read -r host ssh_user <<<"$meta"

  echo "==> checking $node at $ssh_user@$host"
  if ! ssh "${ssh_opts[@]}" "$ssh_user@$host" true; then
    echo "==> WARNING: $node ($ssh_user@$host) is unreachable, skipping" >&2
    continue
  fi

  echo "==> resolving $node closure"
  if ! closure="$(nix "${nix_args[@]}" eval --raw \
    "$repo#deploy.nodes.$node.profiles.system.path.outPath")"; then
    echo "==> WARNING: failed to resolve $node closure, skipping" >&2
    continue
  fi

  node_host[$node]="$host"
  node_ssh_user[$node]="$ssh_user"
  node_closure[$node]="$closure"
  deploy_nodes+=("$node")
done

if [ ${#deploy_nodes[@]} -eq 0 ]; then
  echo "==> ERROR: no hosts were reachable and deployable" >&2
  exit 1
fi

# Copy a closure through this runner (nixbuild -> runner -> host). Used when the
# host-side pull is unavailable or failed.
copy_via_runner() {
  local ssh_user="$1" host="$2" closure="$3" node="$4"
  if ! nix "${nix_args[@]}" copy \
    --from "$remote_store" \
    --to "ssh://$ssh_user@$host" \
    --no-check-sigs \
    -s \
    "$closure"; then
    # nixbuild.net documents that direct copies from a remote store can be
    # inconsistent; fall back to staging the closure locally first.
    echo "==> direct copy for $node failed, retrying via local store" >&2
    nix "${nix_args[@]}" copy --from "$remote_store" --no-check-sigs "$closure"
    nix "${nix_args[@]}" copy --to "ssh://$ssh_user@$host" --no-check-sigs -s "$closure"
  fi
}

# 2) Get each closure onto the host, in parallel. Preferred path: the host
#    pulls straight from nixbuild.net (needs NIXBUILDNET_TOKEN). Fallback: copy
#    through this runner.
pids=()
for node in "${deploy_nodes[@]}"; do
  (
    host="${node_host[$node]}"
    ssh_user="${node_ssh_user[$node]}"
    closure="${node_closure[$node]}"
    tag="$(printf '%-18s' "$node")"

    # Prefix every line with the node name; the copies run in parallel and
    # would otherwise interleave. pipefail (inherited) keeps the pipeline's
    # status equal to the body's, so `wait` still detects failures.
    {
      if [ -z "${NIXBUILDNET_TOKEN:-}" ]; then
        echo "NIXBUILDNET_TOKEN not set; copying via this runner" >&2
        copy_via_runner "$ssh_user" "$host" "$closure" "$node"
      elif [ "$nb_host" = "$remote_store" ]; then
        echo "REMOTE_STORE=$remote_store is not ssh-ng://; copying via this runner" >&2
        copy_via_runner "$ssh_user" "$host" "$closure" "$node"
      elif pull_on_host "$ssh_user" "$host" "$closure"; then
        echo "pulled $closure directly from ssh://$nb_host"
      else
        echo "host-side pull failed; copying via this runner" >&2
        copy_via_runner "$ssh_user" "$host" "$closure" "$node"
      fi
    } 2>&1 | sed -u "s|^|$tag > |"
  ) &
  pids+=("$!")
done

declare -A push_failed
for i in "${!pids[@]}"; do
  node="${deploy_nodes[$i]}"
  if ! wait "${pids[$i]}"; then
    echo "==> WARNING: failed to prepare $node on ${node_ssh_user[$node]}@${node_host[$node]}, skipping" >&2
    push_failed[$node]=1
  fi
done

# 3) Deploy each prepared node independently, so a failure on one host does not
#    stop the others (the remote build deploy-rs performs finds the closure
#    already valid, so each just activates).
deploy_nodes_ok=()
for node in "${deploy_nodes[@]}"; do
  [ -n "${push_failed[$node]:-}" ] && continue
  deploy_nodes_ok+=("$node")
done

if [ ${#deploy_nodes_ok[@]} -eq 0 ]; then
  echo "==> ERROR: no hosts were successfully prepared" >&2
  exit 1
fi

pids=()
for node in "${deploy_nodes_ok[@]}"; do
  (
    tag="$(printf '%-18s' "$node")"
    {
      deploy "$repo#$node" --auto-rollback false --magic-rollback false --skip-checks "$@" -- --accept-flake-config --extra-experimental-features flakes -L
    } 2>&1 | sed -u "s|^|$tag > |"
  ) &
  pids+=("$!")
done

deploy_failed=()
for i in "${!pids[@]}"; do
  node="${deploy_nodes_ok[$i]}"
  if ! wait "${pids[$i]}"; then
    echo "==> WARNING: deployment to $node failed; other nodes were still deployed" >&2
    deploy_failed+=("$node")
  fi
done

if [ ${#deploy_failed[@]} -gt 0 ]; then
  echo "==> ERROR: deployment failed on: ${deploy_failed[*]}" >&2
  exit 1
fi
