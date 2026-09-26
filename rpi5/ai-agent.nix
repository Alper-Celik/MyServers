# SSH access for the Hermes agent (running on hetzner-server-1) to the rpi5
# music library. Dedicated non-wheel user whose data privileges come from the
# ACL rule in syncthing.nix (`user:ai-agent:rwX` on the Music directory) —
# deliberately NOT an entry in `personal-ssh-public-keys` (that list is
# `trusted-ssh-keys`: authorized_keys for root and the normal user on all
# hosts).
#
# The login shell is a systemd-run invocation (transient user service): the
# whole session tree runs with NoNewPrivileges (suid/setcap binaries are
# inert), ProtectSystem=strict with write access confined to the agent's own
# home and the Music directory, and PrivateTmp. Fails closed: if the user
# manager is unreachable or the hardened namespace can't be set up, the
# session refuses rather than dropping hardening.
{ pkgs, ... }:
let
  ai-home = "/var/lib/ai-agent";
  music-dir = "/var/lib/syncthing/data/Music";
  # writeShellScriptBin + shellPath: NixOS `types.shellPackage` requires a
  # `shellPath` attribute, and toShellPath renders the login shell as
  # /run/current-system/sw/bin/ai-agent-shell — hence the systemPackages entry
  # below, so the binary actually exists at that path.
  ai-agent-shell =
    (pkgs.writeShellScriptBin "ai-agent-shell" ''
      set -u
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      # pam_systemd starts the user manager during session setup; give it a
      # moment rather than racing it.
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -S "$XDG_RUNTIME_DIR/systemd/private" ] && break
        sleep 0.3
      done
      HARDENING=(
        --user --collect --pipe
        -p NoNewPrivileges=yes
        -p ProtectSystem=strict
        -p PrivateTmp=yes
        -p "ReadWritePaths=${ai-home} ${music-dir}"
      )
      if [ "''${1:-}" = "-c" ]; then
        exec systemd-run "''${HARDENING[@]}" ${pkgs.fish}/bin/fish -c "$2"
      else
        exec systemd-run "''${HARDENING[@]}" ${pkgs.fish}/bin/fish --login
      fi
      echo "ai-agent-shell: user manager unreachable, refusing unhardened session" >&2
      exit 1
    '')
    // { shellPath = "/bin/ai-agent-shell"; };
in
{
  users.users.ai-agent = {
    isNormalUser = true;
    home = ai-home;
    group = "ai-agent";
    shell = ai-agent-shell;
    openssh.authorizedKeys.keys = [
      # `cat ~/.ssh/id_ed25519.pub` on hetzner-server-1
      # `restrict` = no-port-forwarding,no-X11-forwarding,no-agent-forwarding,
      # no-pty,no-user-rc: the session cannot open tunnels or piggyback on
      # credentials/agents — the SSH analogue of NoNewPrivileges. The agent
      # runs commands non-interactively (BatchMode), so no-pty is no loss.
      "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA5cCv6Jsy6+D+syem7379dSJTeaGJXRsJIbyhK3Uctr hermes-agent@hetzner-server-1"
    ];
    # no `extraGroups = [ "wheel" ]`: the agent gets no sudo. Account has no
    # password (and sshd has PasswordAuthentication/KbdInteractive off), so
    # password login is impossible too.
  };

  environment.shells = [ ai-agent-shell ];
  environment.systemPackages = [ ai-agent-shell ]; # /run/current-system/sw/bin for toShellPath

  # explicit same-name primary group: the ACL in syncthing.nix emits a
  # group:ai-agent ACE, so the group must exist deterministically
  users.groups.ai-agent = { };

  # Defense in depth at the sshd level: the bans hold for ANY key ever added
  # to this user, and AuthorizedKeysFile is pinned to the nix-managed file so
  # the user cannot mint credentials in its own ~/.ssh even though its home is
  # writable. extraConfig renders at the tail of sshd_config — the only legal
  # Match position; no other Match block exists in the fleet's sshd config.
  services.openssh.extraConfig = ''
    Match User ai-agent
        AllowTcpForwarding no
        AllowAgentForwarding no
        X11Forwarding no
        PermitTunnel no
        PermitUserRC no
        AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
  '';

  systemd.tmpfiles.rules = [
    # the Music ACL lives in syncthing.nix with the other data-dir ACLs
    "d ${ai-home} 0750 ai-agent ai-agent - -"
  ];
}
