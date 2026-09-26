# SSH access for the Hermes agent (on hetzner-server-1) to the rpi5 music
# library. The data grant is the ACL rule in syncthing.nix; this file only
# creates the account and pins down what a session can do.
{ config, pkgs, ... }:
let
  ai-home = "/var/lib/ai-agent";
  music-dir = "/var/lib/syncthing/data/Music";

  # Login shell = transient user unit, so the sandbox properties below cover
  # the whole session. systemd-run returns immediately unless told to wait,
  # and a shell without root needs --user; --pipe also carries stdin, stdout
  # and the exit code through.
  ai-agent-shell = pkgs.writeShellScriptBin "ai-agent-shell" ''
    exec ${config.systemd.package}/bin/systemd-run --user --pipe --collect \
      -p NoNewPrivileges=yes \
      -p ProtectSystem=strict \
      -p PrivateTmp=yes \
      -p "ReadWritePaths=${ai-home} ${music-dir}" \
      ${pkgs.fish}/bin/fish "$@"
  '';
in
{
  users.users.ai-agent = {
    isNormalUser = true;
    home = ai-home;
    group = "ai-agent";
    # the login shell: the script's store path (types.shellPackage wants a
    # passthru.shellPath on derivations, a plain path needs no such dance)
    shell = "${ai-agent-shell}/bin/ai-agent-shell";
    openssh.authorizedKeys.keys = [
      # public half of the key generated on hetzner-server-1; `restrict` = no
      # forwarding, no pty, no rc file.
      "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA5cCv6Jsy6+D+syem7379dSJTeaGJXRsJIbyhK3Uctr hermes-agent@hetzner-server-1"
    ];
  };

  users.groups.ai-agent = { };

  # Holds for any key that could ever be added to this user, and keeps the
  # account from minting keys in its own (writable) home.
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
    "d ${ai-home} 0750 ai-agent ai-agent - -"
  ];
}
