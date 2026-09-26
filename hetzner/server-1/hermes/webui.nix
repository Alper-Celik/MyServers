# Hermes WebUI: runs the agent in-process against HERMES_HOME, so browser
# chats write real Hermes sessions (the open-webui container's transcript DB
# stays disjoint). Loopback-only; the agent.lab caddy vhost is tailnet-only.
{
  config,
  hermesPorts,
  ...
}:

{
  services.hermes-webui = {
    enable = true;
    port = hermesPorts.webui;

    # Gateway's account + managed flag: identical agent behavior in-process.
    user = "hermes";
    group = "hermes";
    extraEnvironment = {
      HERMES_MANAGED = "true";
      # Behind caddy — honor X-Forwarded-Proto so auth cookies get Secure.
      HERMES_WEBUI_TRUST_FORWARDED_PROTO = "1";
      # Warm agent instances pin transcripts in RAM; upstream default is 25.
      HERMES_WEBUI_AGENT_CACHE_MAX = "8";
    };

    hermesHome = "/var/lib/hermes/.hermes";
    stateDir = "/var/lib/hermes/.hermes/webui";

    # Gateway's exact package — HERMES_WEBUI_PYTHON derives from its venv
    # passthru, bootstrap finds run_agent.py through that interpreter.
    agent.package = config.services.hermes-agent.package;
  };

  # The WebUI reads webui_oidc from HERMES_HOME config.yaml, which the agent
  # module renders from its settings option. Public PKCE client (no secret);
  # empty allow_values would disable OIDC entirely.
  services.hermes-agent.settings.webui_oidc = {
    issuer = "https://id.auth.how/realms/private";
    client_id = "hermes-webui";
    redirect_uri = "https://agent.lab.alper-celik.dev/api/auth/oidc/callback";
    allow_claim = "preferred_username";
    allow_values = [ "alper" ];
  };
}
