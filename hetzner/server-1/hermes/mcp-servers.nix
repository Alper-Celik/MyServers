{
  ...
}:

{
  # MCP servers (merged into settings.mcp_servers). Tools register as
  # mcp_<server>_<tool> and are available in every conversation.
  # `\${VAR}` placeholders are resolved by hermes at startup from .env
  # (sops-rendered in secrets.nix); Nix only ever sees the literal placeholder,
  # so no secret value lands in the nix store or config.yaml.
  # GitHub is served by the entry below (pkgs.github-mcp-server, extraPackages
  # in settings.nix); the gh CLI stays installed as well — the two are
  # complementary, the MCP server for typed API work, gh for raw/CLI-shaped
  # work. Exa is the native web-search backend (exa dependency group).
  services.hermes-agent.mcpServers = {
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
    # Server: pkgs.mcp-grafana (extraPackages in settings.nix) — the official Go
    # server, so it needs no interpreter. The previous uvx route
    # (`uvx mcp-grafana==1.6.0`) could never start here: uv's managed CPython is
    # a generic-glibc build, and this host runs environment.stub-ld (the "NixOS
    # cannot run dynamically linked executables" message stub) at
    # /lib/ld-linux-aarch64.so.1 rather than programs.nix-ld, so every
    # uv-managed interpreter exits 127.
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
}
