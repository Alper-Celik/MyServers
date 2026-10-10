{
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    inputs.hermes-agent.nixosModules.default
    inputs.hermes-webui.nixosModules.default
    ./secrets.nix
    ./settings.nix
    ./mcp-servers.nix
    ./web.nix
    ./webui.nix
    ./hindsight.nix
  ];

  # Ports shared by the agent services (settings.nix) and their caddy vhosts
  # (web.nix), declared once here and handed to both as module args.
  _module.args.hermesPorts = {
    api = 8642; # OpenAI-compatible API server (gateway platform)
    dashboard = 9119; # web dashboard / desktop backend
    webui = 8787; # hermes-webui (loopback-only)
  };

  # SSH access for the omp coding agent on the workstation: a dedicated
  # ed25519 key whose authorized_keys entry forces the command to
  # `hermes mcp serve`, so the key can only talk to Hermes' stdio MCP server
  # (send/poll messages into conversations) — no shell, no port forwarding.
  # The omp agent uses this as its fire-and-forget offload channel and as a
  # more relaxed test surface (own user, wider sandbox than its firejail).
  # HERMES_HOME is not needed here: the hermes CLI defaults to ~/.hermes,
  # which is /var/lib/hermes/.hermes for this user — the same state the
  # gateway services use.
  users.users.hermes.openssh.authorizedKeys.keys = [
    ''command="${inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/hermes mcp serve",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINE8Uozb7bw9NZvZrG3QcJh7TsOMJFGzGBvRSfNPty1s omp-hermes-mcp''
  ];

  # programs.nix-ld (configuration.nix) exports NIX_LD / NIX_LD_LIBRARY_PATH to
  # login sessions only — systemd units get a curated environment, and nix-ld's
  # loader panics without NIX_LD. Export them for both agent units so their
  # subprocesses (terminal tool: `uv tool install`, npm native addons, pip
  # manylinux wheels, release tarballs) can run generic binaries.
  # NOTE: MCP stdio servers do NOT inherit this — Hermes passes only
  # PATH/HOME/USER/LANG/LC_ALL/TERM/SHELL/TMPDIR/XDG_* to them, so a uvx-based
  # MCP server needs NIX_LD and NIX_LD_LIBRARY_PATH in its own `env` map.
  systemd.services = {
    hermes-agent.environment = {
      NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    };
    hermes-backend.environment = {
      NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    };
  };
}
