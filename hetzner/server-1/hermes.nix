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
      gh
      fd
      ripgrep
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

    environmentFiles = [ config.sops.templates."hermes-env".path ];

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
