{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  api-port = 8642; # OpenAI-compatible API server (gateway platform)
  dashboard-port = 9119; # web dashboard / desktop backend

  # Voice-note transcription goes through a multimodal model on OpenRouter (ZDR
  # is enforced account-level and requested per call). The script itself is
  # pkgs/hermes-openrouter-stt.js; the shebang is added here so the source file
  # stays plain JS (no `''${` escaping) and node comes from the store rather
  # than the unit PATH.
  sttScript = pkgs.writeTextFile {
    name = "hermes-openrouter-stt";
    executable = true;
    destination = "/bin/hermes-openrouter-stt";
    text = "#!${pkgs.nodejs}/bin/node\n" + builtins.readFile ../../pkgs/hermes-openrouter-stt.js;
  };

  # Offline fallback model for that script (whisper.cpp): small is the
  # speed/quality compromise that still fits the 300 s local-STT timeout on 4
  # cores. large-v3-turbo transcribes far better (and is what OpenRouter is
  # asked for) but runs ~10-15x realtime here.
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
    hash = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
  };
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

  # Git HTTPS credentials for the AGENT's shell — a second, gh-independent
  # route to the same token: `git push` authenticates from this file through
  # git's `store` helper (wired up by the GIT_CONFIG_* variables in
  # `environment` further down) rather than through `gh auth git-credential`
  # from the hand-managed ~/.gitconfig, so HTTPS pushes keep working even if
  # gh is dropped again. Belongs to the same reasoning as the gh block above:
  # hermes strips Tier-1 secrets — GITHUB_TOKEN / GH_TOKEN — from every
  # terminal and execute_code child, and `terminal.env_passthrough` cannot
  # re-allow them (provider/tool credentials are blocked on purpose,
  # GHSA-rhgp-j443-p4rf). git's store helper reads $HOME/.git-credentials, and
  # on the LOCAL terminal backend files are simply accessible — the documented
  # route for file credentials.
  # Format: one `https://user:token@host` line per host, 0600, owner hermes.
  sops.templates."git-credentials" = {
    content = ''
      https://Alper-Celiks-Agent:${config.sops.placeholder.GITHUB_TOKEN_AI}@github.com
    '';
    path = "/var/lib/hermes/.git-credentials";
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
    # github-mcp-server: the GitHub MCP stdio server below, likewise a
    #   nix-built Go binary (no interpreter)
    # gh: the GitHub CLI, still here alongside the MCP server — it reads the
    #   sops-rendered ~/.config/gh/hosts.yml above, and covers what the MCP
    #   server does not (raw `gh api`, `gh run watch`, ad-hoc `gh pr` output)
    extraPackages = with pkgs; [
      nix
      chromium
      git
      fd
      ripgrep
      uv
      gh
      mcp-grafana
      github-mcp-server
      # whisper-cli: OFFLINE fallback for the STT script below (node itself is
      # pinned by the script's store shebang). ffmpeg, needed to turn the
      # Telegram .ogg into 16 kHz wav, is already on the unit PATH from the module.
      whisper-cpp
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
      # Writes to agent-instruction files (AGENTS.md/CLAUDE.md/SOUL.md/
      # .cursorrules, project-local .hermes config) normally require human
      # approval even under yolo. The gate covers only the AGENT'S file-edit
      # tools: a plain shell write to the same file is not gated by it at all,
      # so it stops the careful path and nothing else — and on this host the
      # approval prompt is delivered to the dashboard/Telegram surface where a
      # timeout counts as DENY, which silently blocks legitimate policy edits
      # (e.g. adding the worktree rule to AGENTS.md). The real protection for
      # instruction files is the PR route: agent edits land as reviewed
      # Alper-Celik/* pull requests, never as direct workspace writes.
      security.protected_instruction_files = false;
      model = {
        base_url = "https://openrouter.ai/api/v1";
        default = "@preset/hermes-agent";
        context_length = 900000;
      };
      api_server = {
        enabled = true;
        port = 8642;
      };
      # GitHub /ac_agent trigger endpoint. GitHub POSTs comment events here and the
      # route's script decides whether the comment is a real /ac_agent request
      # (marker + allow-listed author) before anything runs. The adapter binds
      # LOOPBACK ONLY on purpose: caddy is the sole public surface, and only for
      # the single /webhooks/github-ac-agent path (see the virtualHosts block at
      # the bottom of this file). Per-route HMAC secrets live in
      # $HERMES_HOME/webhook_subscriptions.json (runtime state, not nix-managed),
      # so no secret belongs in this file or in the sops-rendered .env.
      platforms.webhook = {
        enabled = true;
        extra = {
          host = "127.0.0.1";
          port = 8644;
        };
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
    # GitHub is served by the entry below (pkgs.github-mcp-server, extraPackages
    # above); the gh CLI stays installed as well — the two are complementary,
    # the MCP server for typed API work, gh for raw/CLI-shaped work. Exa is the
    # native web-search backend (exa dependency group).
    mcpServers = {
      # GitHub — the official MCP server, nix-packaged so it needs no uvx/npx
      # interpreter (uv's managed CPython cannot run on this host; see the
      # grafana comment below). Tools register as mcp__github__* — repos,
      # issues, PRs and reviews, branch/commit/file writes, code search, and
      # via `actions` the CI runs/jobs (`gh pr checks` equivalent, so
      # "is CI green" stays answerable).
      # `--toolsets`: default = context, copilot, issues, pull_requests, repos,
      # users (43 tools); +actions = 47. Use `all` for 82 (gists, notifications,
      # dependabot, discussions, projects, …) — every tool costs context in
      # every conversation, so widen only when a task needs it.
      # The token MUST ride in this env map: stdio children inherit only a
      # filtered env (PATH/HOME/USER/XDG_*), and ${GITHUB_TOKEN} is resolved by
      # hermes at startup from the sops-rendered .env — never from Nix.
      # Writes are enabled (the agent opens PRs); add "--read-only" to args to
      # make the server hard-read-only for non-PR work.
      github = {
        command = "github-mcp-server";
        args = [
          "stdio"
          "--toolsets=default,actions"
        ];
        env.GITHUB_PERSONAL_ACCESS_TOKEN = "\${GITHUB_TOKEN}";
        timeout = 300;
      };

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
    # to be a verified email on the bot GitHub account (MCP/API actions — PRs,
    # issues — attribute to the GITHUB_TOKEN account automatically).
    # GIT_CONFIG_* wires git's credential `store` helper to the sops-rendered
    # ~/.git-credentials without editing ~/.gitconfig (hand-managed on the
    # host; it keeps its own `gh auth git-credential` line, whose nix-store path
    # would go stale were gh ever dropped again). Env-config entries outrank
    # file config, so `store` is consulted first while the gh helper stays as a
    # fallback; verified with `git credential fill` against a failing
    # file-level helper. git >= 2.31 (host runs 2.54).
    environment = {
      GIT_AUTHOR_NAME = "hermes-agent";
      GIT_COMMITTER_NAME = "hermes-agent";
      GIT_AUTHOR_EMAIL = "agent@alper-celik.dev";
      GIT_COMMITTER_EMAIL = "agent@alper-celik.dev";
      GIT_CONFIG_COUNT = "1";
      GIT_CONFIG_KEY_0 = "credential.https://github.com.helper";
      GIT_CONFIG_VALUE_0 = "store";

      # Voice-note transcription (Telegram voice messages). Without this, every
      # voice note fails with "No STT provider available":
      #   - the bundled default (faster-whisper) cannot be lazy-installed on a
      #     nixos-managed install ("Feature 'stt.faster_whisper' unavailable:
      #     unsupported on nixos-managed installs"), and the dependency group
      #     would compile 31 derivations from source on aarch64;
      #   - Hermes' local-CLI detector looks for a binary named exactly
      #     `whisper`, while whisper.cpp ships `whisper-cli` — no match;
      #   - no first-party cloud STT key is configured.
      # HERMES_LOCAL_STT_COMMAND is the documented escape hatch: the value runs
      # through shlex.split (no shell — no pipes/globs) and must leave a .txt in
      # {output_dir}. It points at a small script (pkgs/hermes-openrouter-stt.js)
      # that posts the audio to a multimodal model on OpenRouter — ~2 s per note
      # and no CPU load, versus ~10-15x realtime for a local whisper.cpp model on
      # this box's 4 cores. ZDR is enforced account-level and requested per call
      # (provider.zdr). The script falls back to whisper-cli below if the API is
      # unreachable, so an outage degrades to slow, not broken.
      # It also asks the model to tag non-neutral delivery ([sarcastic],
      # [joking], …) so tone survives the transcription; OR_STT_TONE=0 disables.
      HERMES_LOCAL_STT_COMMAND = "${sttScript}/bin/hermes-openrouter-stt {input_path} {output_dir}";
      OR_STT_WHISPER_MODEL = "${whisperModel}";
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
      - Work in a dedicated git worktree for every task, never in a shared
        checkout: `git fetch origin && git worktree add -b agent/<topic>
        ../<repo>-<topic> origin/main`, then do all edits and commits there.
        Other agents keep in-flight branches checked out in
        `~/workspace/<repo>`, so committing in the shared tree steps on their
        work; run `git worktree list` first and leave their branches alone.
        Branch from freshly fetched `origin/main`, not from whatever branch the
        shared checkout happens to have checked out. Remove the worktree once
        its PR has merged.
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
      extraConfig = lib.mkMerge [
        # Public trigger path for the GitHub /ac_agent webhook.
        #
        # common/caddy.nix blocks every request whose client IP is outside the
        # tailnet with a 403 (@not_local_ip, emitted at mkOrder 400). GitHub's
        # delivery IPs are obviously not on the tailnet, so this ONE path is
        # exempted — mkOrder 100 lands it before that guard; `caddy adapt` on the
        # generated Caddyfile confirms the path matcher precedes the
        # static_response 403 in the site's handler chain.
        #
        # Exposure: the path is HMAC-SHA256 authenticated by the hermes webhook
        # adapter (per-route secret in webhook_subscriptions.json) AND the route's
        # script re-checks the comment author against an allow-list, so an
        # unsigned or non-allow-listed POST runs nothing. Everything else on this
        # vhost — the dashboard — stays tailnet-only, and the adapter itself
        # listens on loopback (platforms.webhook.extra.host above).
        (lib.mkOrder 100 ''
          @github_ac_agent path /webhooks/github-ac-agent*
          handle @github_ac_agent {
            reverse_proxy 127.0.0.1:8644
          }
        '')
        "reverse_proxy http://localhost:${toString dashboard-port}"
      ];
    };
    "hermes-api.lab.alper-celik.dev" = {
      extraConfig = "reverse_proxy http://localhost:${toString api-port}";
    };
  };
}
