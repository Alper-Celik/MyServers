{ ... }:
{
  # Env-file secret, added by Alper to the private MyServersSecrets repo
  # (secrets/ovhcloud/server-1.yaml — see the PR body for the exact contents).
  # One key feeds hindsight's LLM role, embeddings and the openrouter fallback
  # chain; hindsight reads its own variable names, so the file carries them:
  #   HINDSIGHT_API_OPENROUTER_API_KEY=sk-or-v1-...
  #   HINDSIGHT_API_LLM_API_KEY=sk-or-v1-...
  sops.secrets."hindsight_env" = { };
}
