{
  lib,
  hermesPorts,
  ...
}:

{
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
        # listens on loopback (platforms.webhook.extra.host in settings.nix).
        (lib.mkOrder 100 ''
          @github_ac_agent path /webhooks/github-ac-agent*
          handle @github_ac_agent {
            reverse_proxy 127.0.0.1:8644
          }
        '')
        "reverse_proxy http://localhost:${toString hermesPorts.dashboard}"
      ];
    };
    "hermes-api.lab.alper-celik.dev" = {
      extraConfig = "reverse_proxy http://localhost:${toString hermesPorts.api}";
    };
  };
}
