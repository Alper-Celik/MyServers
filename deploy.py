#!/usr/bin/env nix
#! nix shell .#deploy-env --command python3
# ai generated (port of the bash deploy.sh this replaces)
"""Deploy this flake's NixOS hosts.

Subcommands:
  deploy      build on the remote store, then copy closures and switch to them
  deploy-ci   copy closures and switch to them (CI already built them)
  boot        copy closures and make them the boot default (no activation)
  reboot      copy closures, make them the boot default, then reboot
  build       run the CI build step against the remote store (all nodes)
  resolve     resolve reachable hosts and their closure paths
  copy        resolve hosts, then get each closure onto its host
  activate    resolve hosts, then switch them to their closure over SSH

Every subcommand except build takes an optional list of node names to limit
the run, e.g. `deploy.py reboot rpi5`.

Activation installs the copied closure as the system profile and runs
switch-to-configuration on the host — the same thing nixos-rebuild does
remotely — so no deploy-rs (and no per-host flake evaluation) is involved.

Extra arguments are only forwarded to the build step.

Closures are pulled from the remote store either by the host itself (using
NIXBUILDNET_TOKEN, or a short-lived store:read token minted from the local
nixbuild.net SSH key through the administration shell, which needs that key to
hold account:write) or, as a fallback, copied through this runner — so a
machine with only an SSH key to nixbuild.net works too, just slower.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import tempfile
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent
REMOTE_STORE = os.environ.get("REMOTE_STORE", "ssh-ng://eu.nixbuild.net")
NODES = ["ovhcloud-server-1", "hetzner-server-1", "rpi5"]
NIX_ARGS = ["--extra-experimental-features", "nix-command flakes"]
SSH_OPTS = ["-o", "ConnectTimeout=10", "-o", "BatchMode=yes"]

# Attribute checked by the CI build step (builds/validates every deploy node).
CHECK_ATTR = "checks.aarch64-linux.deploy-toplevels"

# Pinned nixbuild.net host key (same one nixbuild-action uses).
NB_HOST = REMOTE_STORE.removeprefix("ssh-ng://")
NB_HOST_KEY = (
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM"
)
REMOTE_DIR = "/run/deploy-nixbuild"

# Suffix of the nixbuild.net administration shell's prompt ("nixbuild.net> ",
# "eu.nixbuild.net> "). Session output is prefixed with it, command-argument
# output is not.
PROMPT = "nixbuild.net>"

# Run on each host (via `bash -s`, since the remote login shell may be fish):
# install the copied closure as the system profile generation, then run
# switch-to-configuration. `action` is one of switch/boot/reboot, where reboot
# means boot + reboot. These are the steps `nixos-rebuild` performs remotely.
# Binaries are resolved by absolute path because a non-interactive SSH command
# may not have them on PATH. `cd /tmp` avoids the deleted-cwd failure
# (nixpkgs#73404) that deploy-rs also worked around.
ACTIVATE_SCRIPT = """\
set -euo pipefail
closure="$1"; action="$2"

find_bin() {
  for c in "/run/current-system/sw/bin/$1" "/nix/var/nix/profiles/default/bin/$1"; do
    if [ -x "$c" ]; then printf '%s\\n' "$c"; return; fi
  done
  printf '%s\\n' "$1"
}

do_reboot=0
if [ "$action" = reboot ]; then
  action=boot
  do_reboot=1
fi
case "$action" in
  switch | boot) ;;
  *)
    echo "unknown activation action: $action" >&2
    exit 2
    ;;
esac

"$(find_bin nix-env)" -p /nix/var/nix/profiles/system --set "$closure"
cd /tmp
"$closure/bin/switch-to-configuration" "$action"

# Detach so the SSH channel closes (and reports success) before the host goes
# down; the reboot fires a few seconds later.
if [ "$do_reboot" = 1 ]; then
  ( "$(find_bin sleep)" 3; "$(find_bin systemctl)" reboot ) >/dev/null 2>&1 </dev/null &
fi
"""

SETUP_SCRIPT = """\
set -euo pipefail
umask 077
rm -rf "$1"
mkdir -p "$1"
"""

PULL_SCRIPT = """\
set -euo pipefail
remote_dir="$1"; pull_store="$2"; closure="$3"
nixbin=""
for c in /run/current-system/sw/bin/nix /nix/var/nix/profiles/default/bin/nix; do
  [ -x "$c" ] && nixbin="$c" && break
done
[ -n "$nixbin" ] || nixbin=nix
NIXBUILDNET_TOKEN="$(cat "$remote_dir/token")" \\
  NIX_SSHOPTS="-F $remote_dir/ssh_config" \\
  "$nixbin" --extra-experimental-features nix-command \\
  copy --from "$pull_store" --no-check-sigs "$closure"
"""


def warn(msg: str) -> None:
    print(f"==> {msg}", file=sys.stderr, flush=True)


def stream(argv, *, stdin_data=None, env=None, tag=None) -> int:
    """Run argv, forwarding merged stdout+stderr line by line, optionally
    prefixed with the node name (output of parallel nodes would otherwise
    interleave)."""
    p = subprocess.Popen(
        argv,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    if stdin_data is not None:
        p.stdin.write(stdin_data)
    p.stdin.close()
    prefix = f"{tag} > " if tag else ""
    for line in p.stdout:
        sys.stdout.write(f"{prefix}{line}")
        sys.stdout.flush()
    p.stdout.close()
    return p.wait()


def ssh_cmd(user: str, host: str, remote: str, *, stdin_data=None, tag=None) -> int:
    return stream(
        ["ssh", *SSH_OPTS, f"{user}@{host}", remote],
        stdin_data=stdin_data,
        tag=tag,
    )


def say(tag: str, msg: str, *, err: bool = False) -> None:
    print(f"{tag} > {msg}", file=sys.stderr if err else sys.stdout, flush=True)


def pull_on_host(ssh_user: str, host: str, closure: str, tag: str) -> bool:
    """Pull the closure directly on the target from nixbuild.net using the
    token for this run only. nixbuild -> host traffic then never touches this
    runner (no download-then-upload hop) and every host pulls at its own
    speed. The token is written into a 0600 ssh config on the target (tmpfs)
    and removed afterwards.

    The remote login shell may be fish, so every command is run explicitly
    through bash instead of relying on the target's shell.

    Returns False if the target could not pull, so the caller can fall back to
    copying through this runner."""
    token = os.environ["NIXBUILDNET_TOKEN"].strip("\r\n")
    rdir = shlex.quote(REMOTE_DIR)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "known_hosts").write_text(f"{NB_HOST} {NB_HOST_KEY}\n")
        (tmp / "token").write_text(token)
        (tmp / "ssh_config").write_text(
            f"Host {NB_HOST}\n"
            f"  HostName {NB_HOST}\n"
            "  User authtoken\n"
            "  PreferredAuthentications none\n"
            "  PubkeyAcceptedKeyTypes ssh-ed25519\n"
            "  StrictHostKeyChecking yes\n"
            f"  UserKnownHostsFile {REMOTE_DIR}/known_hosts\n"
            "  ControlPath none\n"
            "  ServerAliveInterval 60\n"
            "  IPQoS throughput\n"
            f"  SetEnv token={token}\n"
            "  SendEnv NIXBUILDNET_TOKEN\n"
        )

        ok = (
            ssh_cmd(ssh_user, host, f"bash -s -- {rdir}", stdin_data=SETUP_SCRIPT, tag=tag)
            == 0
        )
        if ok:
            for name in ("known_hosts", "ssh_config", "token"):
                data = (tmp / name).read_text()
                ok &= (
                    ssh_cmd(
                        ssh_user,
                        host,
                        f"bash -c 'umask 077; cat > \"$1\"' _ {rdir}/{name}",
                        stdin_data=data,
                        tag=tag,
                    )
                    == 0
                )
        if ok:
            say(
                tag,
                f"==> {host}: pulling {closure} from ssh://{NB_HOST} on the host",
                err=True,
            )
            ok &= (
                ssh_cmd(
                    ssh_user,
                    host,
                    f"bash -s -- {rdir} {shlex.quote(f'ssh://{NB_HOST}')} {shlex.quote(closure)}",
                    stdin_data=PULL_SCRIPT,
                    tag=tag,
                )
                == 0
            )

        ssh_cmd(ssh_user, host, f"bash -c 'rm -rf \"$1\"' _ {rdir}", tag=tag)
        return ok


def copy_via_runner(ssh_user: str, host: str, closure: str, node: str, tag: str) -> bool:
    """Copy a closure through this runner (nixbuild -> runner -> host). Used
    when the host-side pull is unavailable or failed."""
    to_host = ["--to", f"ssh://{ssh_user}@{host}", "--no-check-sigs", "-s", closure]
    if stream(["nix", *NIX_ARGS, "copy", "--from", REMOTE_STORE, *to_host], tag=tag) == 0:
        return True
    # nixbuild.net documents that direct copies from a remote store can be
    # inconsistent; fall back to staging the closure locally first.
    say(tag, f"==> direct copy for {node} failed, retrying via local store", err=True)
    if stream(["nix", *NIX_ARGS, "copy", "--from", REMOTE_STORE, "--no-check-sigs", closure], tag=tag) != 0:
        return False
    return stream(["nix", *NIX_ARGS, "copy", *to_host], tag=tag) == 0


def prepare_node(node: str, meta: dict) -> bool:
    host, ssh_user, closure = meta[node]
    tag = f"{node:<18}"
    if "NIXBUILDNET_TOKEN" not in os.environ:
        say(tag, "NIXBUILDNET_TOKEN not set; copying via this runner", err=True)
        return copy_via_runner(ssh_user, host, closure, node, tag)
    if NB_HOST == REMOTE_STORE:
        say(
            tag,
            f"REMOTE_STORE={REMOTE_STORE} is not ssh-ng://; copying via this runner",
            err=True,
        )
        return copy_via_runner(ssh_user, host, closure, node, tag)
    if pull_on_host(ssh_user, host, closure, tag):
        say(tag, f"pulled {closure} directly from ssh://{NB_HOST}")
        return True
    say(tag, "host-side pull failed; copying via this runner", err=True)
    return copy_via_runner(ssh_user, host, closure, node, tag)


def select_nodes(hosts: list[str]) -> list[str] | None:
    """Restrict to the requested nodes (kept in NODES order), or all nodes when
    none are given. Returns None if a requested node is unknown."""
    if not hosts:
        return list(NODES)
    unknown = [h for h in hosts if h not in NODES]
    if unknown:
        warn(f"ERROR: unknown node(s): {' '.join(unknown)} (known: {' '.join(NODES)})")
        return None
    return [n for n in NODES if n in hosts]


def evaluate_nodes(selected: list[str]) -> dict | None:
    """Evaluate the selected nodes' hosts and closure paths from the flake.

    The closures are already built in the remote store by the build step, so
    this evaluates but does not build. One evaluation covers every selected
    node (instead of one full flake/config evaluation per node), and it is
    masked to the selection so that an unselected node's closure is never
    evaluated.

    Returns the deploy table (node -> hostname/sshUser/closure), or None."""
    # Only force the selected nodes: the JSON output realises every value it
    # prints, and each closure costs a full NixOS evaluation.
    mask = " ".join(f"{json.dumps(node)} = null;" for node in selected)
    p = subprocess.run(
        [
            "nix",
            *NIX_ARGS,
            "eval",
            "--json",
            f"{REPO}#deploy-nodes",
            "--apply",
            "nodes: builtins.mapAttrs (n: v: {"
            " hostname = v.hostname;"
            " sshUser = v.sshUser;"
            " closure = v.toplevel.outPath;"
            f" }}) (builtins.intersectAttrs {{ {mask} }} nodes)",
        ],
        stdout=subprocess.PIPE,
        text=True,
    )
    if p.returncode != 0:
        warn("ERROR: failed to evaluate deploy-nodes")
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        warn("ERROR: failed to decode deploy-nodes evaluation")
        return None


def resolve_hosts(
    hosts: list[str], nodes: dict | None = None
) -> tuple[dict[str, tuple[str, str, str]], list[str]] | None:
    """Resolve the selected nodes' hosts and closure paths.

    `nodes` is the deploy table a previous build step produced (see
    build_nodes). When it is absent — a deploy that did not build, e.g. CI
    where the build ran in an earlier job — the table is evaluated from the
    flake here, in one evaluation covering the whole selection.

    Returns (meta, deploy_nodes), or None on evaluation or selection failure."""
    selected = select_nodes(hosts)
    if selected is None:
        return None
    if nodes is None:
        nodes = evaluate_nodes(selected)
        if nodes is None:
            return None

    meta: dict[str, tuple[str, str, str]] = {}
    deploy_nodes: list[str] = []
    for node in selected:
        info = nodes.get(node)
        if info is None:
            warn(f"WARNING: {node} is not defined in deploy-nodes, skipping")
            continue
        host, ssh_user, closure = info["hostname"], info["sshUser"], info["closure"]
        print(f"==> checking {node} at {ssh_user}@{host}", flush=True)
        if subprocess.run(["ssh", *SSH_OPTS, f"{ssh_user}@{host}", "true"]).returncode != 0:
            warn(f"WARNING: {node} ({ssh_user}@{host}) is unreachable, skipping")
            continue
        meta[node] = (host, ssh_user, closure)
        deploy_nodes.append(node)

    if not deploy_nodes:
        warn("ERROR: no hosts were reachable and deployable")
        return None
    return meta, deploy_nodes


def shell_lines(text: str) -> list[str]:
    """Non-empty lines of nixbuild.net shell output, with the shell prompt
    removed (session output prefixes each line with it, command-argument
    output does not)."""
    lines = (line.split(PROMPT)[-1].strip() for line in text.splitlines())
    return [line for line in lines if line]


def mint_token() -> str | None:
    """Mint a store-read-only auth token from the local SSH key
    through the nixbuild.net administration shell. Hosts need a token to pull
    from the remote store themselves; on failure this runner copies instead.
    Two hours: big closures over slow home links (e.g. the rpi5) can take a
    while, and the token is store:read-only so a longer TTL is low risk.

    The admin shell requires a name for manually created tokens, and names must
    be unique among the account's active tokens (a name can only be reused once
    the previous token expired), so every run mints under its own name.

    The command is written to a plain shell session instead of being passed as
    an ssh argument: a command argument is authorized as one `run` operation
    (run:write), while a session command is authorized as the shell command
    itself (account:write, what the docs list for the administration shell)."""
    ttl = 7200
    name = f"deploy-{uuid.uuid4().hex[:8]}"
    # Connect without a remote command and write the command (plus `exit`, so
    # the session terminates even if the shell ignores EOF) to its stdin.
    p = subprocess.run(
        ["ssh", *SSH_OPTS, NB_HOST],
        input=f"tokens create --name {name} --ttl-seconds {ttl} -p store:read\nexit\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    # The shell prints the token framed by dashed rules and splits its output
    # over both ssh streams (banner/prompt on one, command output on the
    # other), so parse the two together. The minted token is the only line that
    # is a long run of base64url characters; matching it by shape avoids
    # depending on which stream carried the rules.
    output = shell_lines(p.stderr) + shell_lines(p.stdout)
    token = next(
        (
            line
            for line in output
            if len(line) >= 64
            and any(c.isalnum() for c in line)
            and all(c.isalnum() or c in "-_=" for c in line)
        ),
        None,
    )
    if token:
        warn(
            f"minted a nixbuild.net store:read token {name} from the local SSH key"
            f" (ttl {ttl}s)"
        )
        return token

    # Show everything the shell said: its authorization errors put the reason
    # above a trailing hint line (e.g. about max-cpu-hours-per-month).
    detail = "".join(f"\n      {ln}" for ln in output) or f" ssh exited {p.returncode} with no output"
    warn(
        "could not mint a nixbuild.net token from the local SSH key; copying via this runner:"
        f"{detail}"
    )
    # The shell lists the permissions it wanted after this marker; only those
    # lines name a missing permission (elsewhere "store:read" and friends
    # appear as token permissions).
    marker = next(
        (i for i, ln in enumerate(output) if "one or more of these permissions" in ln), None
    )
    if marker is not None:
        missing = [
            ln
            for ln in output[marker + 1 :]
            if len(parts := ln.split(":")) == 2 and all(p.isalpha() for p in parts)
        ]
        if missing:
            perms = " ".join(f"--add {p}" for p in missing)
            warn(
                f"the SSH key for {NB_HOST} lacks {' '.join(missing)} to run tokens create: "
                f"add it with 'ssh {NB_HOST}' then 'settings default-permissions {perms}' (or "
                "with --ssh-key <id> to add it to that key only), or set NIXBUILDNET_TOKEN "
                "yourself"
            )
    return None


def copy_nodes(meta: dict, deploy_nodes: list[str]) -> set[str]:
    """Get each closure onto the host, in parallel. Preferred path: the host
    pulls straight from the remote store (using NIXBUILDNET_TOKEN, or one
    minted from the local SSH key). Fallback: copy through this runner.
    Returns the set of successfully prepared nodes."""
    if "NIXBUILDNET_TOKEN" not in os.environ and NB_HOST != REMOTE_STORE:
        token = mint_token()
        if token:
            os.environ["NIXBUILDNET_TOKEN"] = token

    push_failed: set[str] = set()
    with ThreadPoolExecutor(max_workers=len(deploy_nodes)) as ex:
        for node, ok in zip(deploy_nodes, ex.map(lambda n: prepare_node(n, meta), deploy_nodes)):
            if not ok:
                host, ssh_user, _ = meta[node]
                warn(f"WARNING: failed to prepare {node} on {ssh_user}@{host}, skipping")
                push_failed.add(node)
    return set(deploy_nodes) - push_failed


def activate_nodes(
    meta: dict, deploy_nodes_ok: list[str], extra: list[str], action: str
) -> int:
    """Activate each prepared node independently (set profile + run
    switch-to-configuration with `action`), so a failure on one host does not
    stop the others."""
    if extra:
        warn(f"WARNING: ignoring extra arguments with direct activation: {' '.join(extra)}")
    deploy_failed: list[str] = []
    with ThreadPoolExecutor(max_workers=len(deploy_nodes_ok)) as ex:
        for node, ok in zip(
            deploy_nodes_ok,
            ex.map(lambda n: deploy_node(n, meta, action), deploy_nodes_ok),
        ):
            if not ok:
                warn(f"WARNING: activation ({action}) failed on {node}; other nodes were still activated")
                deploy_failed.append(node)

    if deploy_failed:
        warn(f"ERROR: activation ({action}) failed on: {' '.join(deploy_failed)}")
        return 1
    return 0


def deploy_node(node: str, meta: dict, action: str) -> bool:
    """Activate the host to its already-copied system closure over SSH: set it
    as the system profile and run switch-to-configuration with `action`
    (switch/boot/reboot). This is what nixos-rebuild does remotely, so no
    deploy-rs (and no per-host flake evaluation or build) is involved."""
    host, ssh_user, closure = meta[node]
    tag = f"{node:<18}"
    return (
        ssh_cmd(
            ssh_user,
            host,
            f"bash -s -- {shlex.quote(closure)} {shlex.quote(action)}",
            stdin_data=ACTIVATE_SCRIPT,
            tag=tag,
        )
        == 0
    )


def build_nodes(extra: list[str]) -> dict | None:
    """Build every deploy node's closure on the remote store — the same check
    the workflow's build/check job builds — and return the deploy table that
    build writes (node -> hostname/sshUser/closure).

    The table is the build's output, so a deploy reads the hosts and closures
    out of the build it just ran instead of evaluating the flake (and every
    NixOS configuration) again. Builds every node; host selection does not
    apply.

    Build logs go to stderr and are streamed, leaving stdout for the JSON
    result."""
    p = subprocess.Popen(
        [
            "nix",
            *NIX_ARGS,
            "build",
            f"{REPO}#{CHECK_ATTR}",
            "-L",
            "--print-build-logs",
            "--builders",
            "",
            "--max-jobs",
            "2",
            "--eval-store",
            "auto",
            "--store",
            REMOTE_STORE,
            "--json",
            *extra,
        ],
        stdout=subprocess.PIPE,
        text=True,
    )
    result = p.stdout.read()
    p.stdout.close()
    if p.wait() != 0:
        warn("ERROR: the build step failed")
        return None
    try:
        manifest = json.loads(result)[0]["outputs"]["out"]
    except (json.JSONDecodeError, IndexError, KeyError, TypeError):
        warn("ERROR: could not read the build result")
        return None
    # Read the manifest straight out of the remote store. Copying it would pull
    # its closure: the JSON names the closures, so the store records them as
    # this file's references, and `nix copy` follows references (the whole
    # system closures would come back to this runner).
    p = subprocess.run(
        ["nix", *NIX_ARGS, "--store", REMOTE_STORE, "store", "cat", manifest],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if p.returncode != 0:
        warn(f"ERROR: could not read the deploy manifest from the remote store: {p.stderr.strip()}")
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        warn("ERROR: could not decode the deploy manifest")
        return None


def cmd_build(extra: list[str], hosts: list[str]) -> int:
    """Same build step as the workflow's build/check job: build the deploy
    checks on the remote store (nixbuild.net), leaving the closures there for
    the hosts to pull. Builds every node; host selection does not apply."""
    return 0 if build_nodes(extra) is not None else 1


def cmd_resolve(extra: list[str], hosts: list[str]) -> int:
    if resolve_hosts(hosts) is None:
        return 1
    return 0


def cmd_copy(extra: list[str], hosts: list[str]) -> int:
    resolved = resolve_hosts(hosts)
    if resolved is None:
        return 1
    meta, deploy_nodes = resolved
    prepared = copy_nodes(meta, deploy_nodes)
    if not prepared:
        warn("ERROR: no hosts were successfully prepared")
        return 1
    return 0


def cmd_activate(extra: list[str], hosts: list[str]) -> int:
    resolved = resolve_hosts(hosts)
    if resolved is None:
        return 1
    meta, deploy_nodes = resolved
    return activate_nodes(meta, deploy_nodes, extra, "switch")


def cmd_activate_selected(
    extra: list[str], hosts: list[str], action: str, nodes: dict | None = None
) -> int:
    """Resolve, copy each closure to its host, then activate with `action`.
    Shared by deploy/deploy-ci/boot/reboot; `nodes` is the deploy table when
    the caller already built (see build_nodes)."""
    resolved = resolve_hosts(hosts, nodes)
    if resolved is None:
        return 1
    meta, deploy_nodes = resolved
    prepared = copy_nodes(meta, deploy_nodes)
    if not prepared:
        warn("ERROR: no hosts were successfully prepared")
        return 1
    return activate_nodes(meta, [n for n in deploy_nodes if n in prepared], extra, action)


def cmd_deploy_ci(extra: list[str], hosts: list[str]) -> int:
    return cmd_activate_selected(extra, hosts, "switch")


def cmd_boot(extra: list[str], hosts: list[str]) -> int:
    return cmd_activate_selected(extra, hosts, "boot")


def cmd_reboot(extra: list[str], hosts: list[str]) -> int:
    return cmd_activate_selected(extra, hosts, "reboot")


def cmd_deploy(extra: list[str], hosts: list[str]) -> int:
    """Build on the remote store, then deploy what that build produced: the
    build reports every node's host and closure, so the deploy phase neither
    evaluates the flake again nor re-derives the closures."""
    nodes = build_nodes(extra)
    if nodes is None:
        return 1
    return cmd_activate_selected(extra, hosts, "switch", nodes)


COMMANDS = {
    "deploy": ("build on the remote store, then copy closures and switch to them", cmd_deploy),
    "deploy-ci": ("copy closures and switch to them (CI already built them)", cmd_deploy_ci),
    "boot": ("copy closures and make them the boot default (no activation)", cmd_boot),
    "reboot": ("copy closures, make them the boot default, then reboot", cmd_reboot),
    "build": ("run the CI build step against the remote store (all nodes)", cmd_build),
    "resolve": ("resolve reachable hosts and their closure paths", cmd_resolve),
    "copy": ("resolve hosts, then get each closure onto its host", cmd_copy),
    "activate": ("resolve hosts, then switch them to their closure over SSH", cmd_activate),
}


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="deploy.py",
        description="Deploy this flake's NixOS hosts (closures live on the remote store).",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    for name, (help_text, _) in COMMANDS.items():
        sp = sub.add_parser(name, help=help_text)
        if name != "build":
            sp.add_argument(
                "hosts",
                nargs="*",
                metavar="HOST",
                help=f"limit to these nodes (default: all of {', '.join(NODES)})",
            )
    ns, extra = parser.parse_known_args()
    hosts = getattr(ns, "hosts", [])
    return COMMANDS[ns.command][1](extra, hosts)


if __name__ == "__main__":
    sys.exit(main())
