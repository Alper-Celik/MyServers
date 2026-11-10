{
  lib,
  ...
}:
{
  # Tailnet HTTPS front for dev surfaces Hermes serves ad hoc — currently the
  # LedgerApp dev server (vite + injected e2e IPC stub) so a phone on the
  # tailnet can browse the app under a stable name.
  #
  # The dev server itself is an ad-hoc process started in the agent's
  # workspace (`nix develop -c vite dev` bound to 127.0.0.1:1420); this vhost
  # only fronts whatever listens on that port. When nothing listens, the vhost
  # answers 502 — it owns no service of its own.
  #
  # Exposure: x-expose stays at its default false, so common/caddy.nix's
  # @not_local_ip guard 403s everything from outside the tailnet/private
  # ranges; the proxy target is loopback, so nothing extra is published.
  services.caddy.virtualHosts."hermes-proxy.lab.alper-celik.dev" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:1420
    '';
  };
}
