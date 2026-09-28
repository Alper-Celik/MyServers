{ config, ... }:
{
  # Alper adds HINDSIGHT_OPENROUTER_API_KEY to secrets/ovhcloud/server-1.yaml.
  # Service-scoped on purpose: each service keeps its own OpenRouter key/quota
  # (hetzner's hermes uses the unprefixed OPENROUTER_API_KEY).
  sops.secrets.HINDSIGHT_OPENROUTER_API_KEY = { };

  # hindsight reads its own variable names, so one key feeds both
  sops.templates."hindsight-env" = {
    content = ''
      HINDSIGHT_API_OPENROUTER_API_KEY=${config.sops.placeholder.HINDSIGHT_OPENROUTER_API_KEY}
      HINDSIGHT_API_LLM_API_KEY=${config.sops.placeholder.HINDSIGHT_OPENROUTER_API_KEY}
    '';
    restartUnits = [
      "${config.virtualisation.oci-containers.containers.hindsight.serviceName}.service"
    ];
  };
}
