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
    GITHUB_TOKEN = { };
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
      GITHUB_TOKEN=${config.sops.placeholder.GITHUB_TOKEN}
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
    # uv for `uvx mcp-grafana` (MCP stdio server below); uv caches it in ~/.cache/uv
    # gh for GitHub (PRs/issues/releases — the github skill drives it; token via GITHUB_TOKEN)
    extraPackages = [
      pkgs.nix
      pkgs.uv
      pkgs.gh
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
        args = [ "-y" "grep-mcp" "--transport" "stdio" ];
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

  services.caddy.virtualHosts = {
    "hermes.lab.alper-celik.dev" = {
      extraConfig = "reverse_proxy http://localhost:${toString dashboard-port}";
    };
    "hermes-api.lab.alper-celik.dev" = {
      extraConfig = "reverse_proxy http://localhost:${toString api-port}";
    };
  };
}
