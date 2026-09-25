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

  # gh CLI credentials for the AGENT's shell (gh comes from extraPackages).
  # Why a file and not the environment: hermes strips Tier-1 secrets —
  # GITHUB_TOKEN / GH_TOKEN — from every terminal and execute_code child, and
  # `terminal.env_passthrough` cannot re-allow them (provider/tool credentials
  # are blocked on purpose, GHSA-rhgp-j443-p4rf; docs: "Hermes-managed provider
  # credentials can never be re-allowed this way"). gh reads
  # ~/.config/gh/hosts.yml instead, and on the LOCAL terminal backend files are
  # simply accessible — the documented route for file credentials.
  # Shape: the bundled github skill's headless fallback (users map + flat
  # oauth_token + user). Verified on this host with
  # `env -u GITHUB_TOKEN -u GH_TOKEN gh auth status` / `gh api /user`. The
  # users map ALONE is rejected by gh ("the token ... is invalid"); the flat
  # `oauth_token:` line is what it actually uses.
  # ~/.gitconfig already runs `gh auth setup-git`, so `git push` over HTTPS
  # picks this up too, and `gh auth token` gives the agent a token for push
  # URLs without any env var.
  sops.templates."gh-hosts" = {
    content = ''
      github.com:
          users:
              Alper-Celiks-Agent:
                  oauth_token: ${config.sops.placeholder.GITHUB_TOKEN_AI}
          git_protocol: https
          oauth_token: ${config.sops.placeholder.GITHUB_TOKEN_AI}
          user: Alper-Celiks-Agent
    '';
    path = "/var/lib/hermes/.config/gh/hosts.yml";
    mode = "0600";
    owner = config.users.users.hermes.name;
    group = config.users.groups.hermes.name;
  };

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    # nix on PATH so the agent can run throwaway tools: nix shell/run/nix-shell
    # mcp-grafana: the Grafana MCP stdio server below, as a nix-built binary —
    #   uvx cannot run it on this host (see the grafana MCP server comment)
    extraPackages = with pkgs; [
      nix
      chromium
      git
      fd
      ripgrep
      uv
      gh
      mcp-grafana
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

      # Home channel = where cron output and proactive notifications land when a
      # job does not name its own target. Declared here rather than in the
      # sops-rendered .env on purpose: activation rewrites .env from scratch, so
      # a hand-added TELEGRAM_HOME_CHANNEL would be deleted by the next deploy.
      # config.yaml is the canonical store (what `/sethome` persists); the env
      # var is only a best-effort mirror of it.
      #
      # thread_id is REQUIRED on this account: the DM runs in topic mode, and a
      # delivery with no thread id lands in Telegram's system-only lobby, where
      # Alper cannot reply and the gateway drops reply_to_message_id. 1089 is the
      # topic Alper actually chats in; TELEGRAM_CRON_THREAD_ID would override it
      # for cron only. `platform` is required by HomeChannel.from_dict.
      gateway.platforms.telegram.home_channel = {
        platform = "telegram";
        chat_id = "1228209533";
        name = "Home";
        thread_id = "1089";
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
      # Use the HOSTED MCP endpoint instead of the `grep-mcp` npm wrapper: the
      # wrapper asks https://grep.app/api/search with User-Agent
      # grep-mcp-ts/1.0.0, and grep.app is now behind a Vercel bot checkpoint
      # that answers every non-browser request with 429 {"code":"challenge"}
      # (the wrapper reports that as a bogus "rate limit exceeded"). The hosted
      # endpoint serves the same index, needs no auth and no local runtime.
      # Tool: mcp__grep_app__searchGitHub — literal/regex code patterns, not
      # keywords (e.g. "useState(", "import React from").
      grep-app = {
        url = "https://mcp.grep.app";
      };

      # Grafana on this host (observe.lab.alper-celik.dev, caddy → 127.0.0.1:3080).
      # enforce_domain=true, so the local URL is rejected — go through caddy.
      # Token: Grafana → Administration → Service accounts → token (Viewer/Admin).
      # Server: pkgs.mcp-grafana (extraPackages above) — the official Go server, so
      # it needs no interpreter. The previous uvx route (`uvx mcp-grafana==1.6.0`)
      # could never start here: uv's managed CPython is a generic-glibc build, and
      # this host runs environment.stub-ld (the "NixOS cannot run dynamically
      # linked executables" message stub) at /lib/ld-linux-aarch64.so.1 rather than
      # programs.nix-ld, so every uv-managed interpreter exits 127.
      # Update by bumping pkgs.mcp-grafana in nixpkgs — there is no version pin here.
      # Wart: 0.14.0 always sets up an OTLP exporter to localhost:4318 and then
      # stalls ~10s at shutdown when no collector answers; OTEL_SDK_DISABLED and
      # OTEL_*_EXPORTER=none do not suppress it.
      grafana = {
        command = "mcp-grafana";
        args = [
          "-transport"
          "stdio"
        ];
        env = {
          GRAFANA_URL = "https://observe.lab.alper-celik.dev";
          GRAFANA_SERVICE_ACCOUNT_TOKEN = "\${GRAFANA_SERVICE_ACCOUNT_TOKEN}";
        };
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
