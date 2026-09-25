{
  inputs,
  config,
  pkgs,
  ...
}:
let
  api-port = 8642; # OpenAI-compatible API server (gateway platform)
  dashboard-port = 9119; # web dashboard / desktop backend
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  # individual keys from inputs.MyServersSecrets secrets/hetzner/server-1.yaml
  sops.secrets = {
    OPENROUTER_API_KEY = { };
    API_SERVER_KEY = { };
    EXA_API_KEY = { };
    TELEGRAM_BOT_TOKEN_AI = { };
    GITHUB_TOKEN_AI = { };
    CONTEXT7_API_KEY = { };
    GRAFANA_SERVICE_ACCOUNT_TOKEN = { };
  };

  # rendered into the env file the gateway reads at startup; the raw secrets
  # stay root-only, only the rendered file is owned by hermes
  sops.templates."hermes-env" = {
    content = ''
      OPENROUTER_API_KEY=${config.sops.placeholder.OPENROUTER_API_KEY}
      API_SERVER_KEY=${config.sops.placeholder.API_SERVER_KEY}
      EXA_API_KEY=${config.sops.placeholder.EXA_API_KEY}
      TELEGRAM_BOT_TOKEN=${config.sops.placeholder.TELEGRAM_BOT_TOKEN_AI}
      GITHUB_TOKEN=${config.sops.placeholder.GITHUB_TOKEN_AI}
      TELEGRAM_ALLOWED_USERS=1228209533
      CONTEXT7_API_KEY=${config.sops.placeholder.CONTEXT7_API_KEY}
      GRAFANA_SERVICE_ACCOUNT_TOKEN=${config.sops.placeholder.GRAFANA_SERVICE_ACCOUNT_TOKEN}
    '';
    owner = config.users.users.hermes.name;
    group = config.users.groups.hermes.name;
    restartUnits = [
      "hermes-agent.service"
      "hermes-backend.service"
    ];
  };

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    # nix on PATH so the agent can run throwaway tools: nix shell/run/nix-shell
    extraPackages = with pkgs; [
      nix
      chromium
      git
      fd
      ripgrep
      uv
      gh
    ];
    extraDependencyGroups = [
      "messaging"
      "exa"
    ];

    settings = {
      plugins.enabled = [
        "hermes-workbench"
      ];
      approvals.mode = "off";
      model = {
        base_url = "https://openrouter.ai/api/v1";
        default = "@preset/hermes-agent";
        context_length = 900000;
      };
      api_server = {
        enabled = true;
        port = 8642;
      };
      gateway.platforms.telegram.extra = {
        drop_pending_on_cold_boot = false;
        status_indicator = true;
        # Optional custom strings (defaults: "Online" / "Offline"):
        status_online = "🟢 Online";
        status_offline = "🔴 Offline";
      };
      gateway.streaming = {
        enabled = true;
        transport = "auto";
      };
      dashboard = {
        public_url = "https://hermes.lab.alper-celik.dev";
        oauth = {
          provider = "self-hosted";
          self_hosted = {
            issuer = "https://id.auth.how/realms/private";
            client_id = "hermes-dashboard";
          };
        };
      };
    };

    # MCP servers (merged into settings.mcp_servers). Tools register as
    # mcp_<server>_<tool> and are available in every conversation.
    # `\${VAR}` placeholders are resolved by hermes at startup from .env
    # (sops-rendered above); Nix only ever sees the literal placeholder, so no
    # secret value lands in the nix store or config.yaml.
    # GitHub is served by the gh CLI (extraPackages above) instead of an MCP
    # server; Exa is the native web-search backend (exa dependency group).
    mcpServers = {
      # Context7 library docs. Works anonymously without the key — to go
      # anonymous, delete both the headers line here and its sops entries.
      context7 = {
        url = "https://mcp.context7.com/mcp";
        headers.Authorization = "Bearer \${CONTEXT7_API_KEY}";
      };

      # grep.app — code search across public GitHub repos (keyless).
      # npx comes from the nodejs bundled in the hermes package wrapper.
      # First run downloads the package into the npm cache.
      grep-app = {
        command = "npx";
        args = [
          "-y"
          "grep-mcp"
          "--transport"
          "stdio"
        ];
        connect_timeout = 180;
      };

      # Grafana on this host (observe.lab.alper-celik.dev, caddy → 127.0.0.1:3080).
      # enforce_domain=true, so the local URL is rejected — go through caddy.
      # Token: Grafana → Administration → Service accounts → token (Viewer/Admin).
      grafana = {
        command = "uvx";
        args = [ "mcp-grafana==1.6.0" ]; # bump to update; uv caches the env
        env = {
          GRAFANA_URL = "https://observe.lab.alper-celik.dev";
          GRAFANA_SERVICE_ACCOUNT_TOKEN = "\${GRAFANA_SERVICE_ACCOUNT_TOKEN}";
        };
        connect_timeout = 300; # first run downloads the package from PyPI
        timeout = 300;
      };
    };

    environmentFiles = [ config.sops.templates."hermes-env".path ];

    # Commit attribution: agent-made commits carry the automation account's
    # identity, never Alper-Celik's personal one. Requires agent@alper-celik.dev
    # to be a verified email on the bot GitHub account (gh API actions —
    # PRs/issues — attribute to the GITHUB_TOKEN account automatically).
    environment = {
      GIT_AUTHOR_NAME = "hermes-agent";
      GIT_COMMITTER_NAME = "hermes-agent";
      GIT_AUTHOR_EMAIL = "agent@alper-celik.dev";
      GIT_COMMITTER_EMAIL = "agent@alper-celik.dev";
    };

    # Workspace policy file, installed on every activation (nix-managed —
    # runtime edits to it are overwritten on deploy).
    workingDirectory = "/var/lib/hermes/workspace";
    documents."AGENTS.md" = ''
      # Agent identity & GitHub policy

      - You are an automated system and must stay clearly distinguishable from
        Alper: commits use the agent@alper-celik.dev identity, and API actions
        (PRs, issues, comments) attribute to the bot account owning
        GITHUB_TOKEN.
      - NEVER open issues, pull requests, discussions, comments or reviews in
        repositories outside Alper-Celik/* — including "helpful" typo fixes or
        bug reports in third-party projects; that is spam. Reading third-party
        code (clone, search, research) is always fine.
      - If work in a third-party project looks like it needs an issue or PR,
        stop and tell Alper what you would file — Alper decides and acts
        personally.
      - Exception: repositories Alper explicitly names for the task at hand.
    '';

    backend = {
      # native hardened systemd service; gateway runs as hermes-agent,
      # the dashboard backend runs as the separate hermes-backend unit
      mode = "dashboard";
      port = dashboard-port;
    };
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

  services.caddy.virtualHosts = {
    "hermes.lab.alper-celik.dev" = {
      extraConfig = "reverse_proxy http://localhost:${toString dashboard-port}";
    };
    "hermes-api.lab.alper-celik.dev" = {
      extraConfig = "reverse_proxy http://localhost:${toString api-port}";
    };
  };
}
