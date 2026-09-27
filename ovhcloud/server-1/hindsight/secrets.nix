{ config, ... }:
{
  # Alper adds OPENROUTER_API_KEY to the private secrets/ovhcloud/server-1.yaml
  sops.secrets.OPENROUTER_API_KEY = { };

  # hindsight reads its own variable names, so one key feeds both
  sops.templates."hindsight-env" = {
    content = ''
      HINDSIGHT_API_OPENROUTER_API_KEY=${config.sops.placeholder.OPENROUTER_API_KEY}
      HINDSIGHT_API_LLM_API_KEY=${config.sops.placeholder.OPENROUTER_API_KEY}
    '';
    restartUnits = [
      "${config.virtualisation.oci-containers.containers.hindsight.serviceName}.service"
    ];
  };
}
