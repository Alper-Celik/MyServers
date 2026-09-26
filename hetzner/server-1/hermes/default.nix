{
  inputs,
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
  ];

  # Ports shared by the agent services (settings.nix) and their caddy vhosts
  # (web.nix), declared once here and handed to both as module args.
  _module.args.hermesPorts = {
    api = 8642; # OpenAI-compatible API server (gateway platform)
    dashboard = 9119; # web dashboard / desktop backend
    webui = 8787; # hermes-webui (loopback-only; no caddy vhost yet)
  };

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
