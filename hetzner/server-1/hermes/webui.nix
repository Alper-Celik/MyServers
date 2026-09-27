{
  config,
  hermesPorts,
  ...
}:

{
  services.hermes-webui = {
    enable = true;
    port = hermesPorts.webui;

    user = "hermes";
    group = "hermes";
    extraEnvironment = {
      HERMES_MANAGED = "true";
      HERMES_WEBUI_TRUST_FORWARDED_PROTO = "1";
      # upstream default is 25; warm instances pin transcripts in RAM
      HERMES_WEBUI_AGENT_CACHE_MAX = "8";
    };

    hermesHome = "/var/lib/hermes/.hermes";
    stateDir = "/var/lib/hermes/.hermes/webui";

    # the gateway's derivation: HERMES_WEBUI_PYTHON comes from its venv passthru
    agent.package = config.services.hermes-agent.package;
  };

  services.hermes-agent.settings.webui_oidc = {
    issuer = "https://id.auth.how/realms/private";
    client_id = "hermes-webui";
    redirect_uri = "https://agent.lab.alper-celik.dev/api/auth/oidc/callback";
    allow_claim = "email";
    # empty allow_values disables OIDC entirely (upstream)
    allow_values = [ "alper@alper-celik.dev" ];
  };
}
