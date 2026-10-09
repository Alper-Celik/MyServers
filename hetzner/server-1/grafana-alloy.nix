{
  config,
  ...
}:
{
  services.alloy = {
    enable = true;
    configPath = "${../../common/grafana-alloy}/hetzner_server_1.alloy";
  };

  # bearer token for the public OTLP ingest endpoint (hetzner_server_1.alloy).
  # systemd reads the EnvironmentFile as root before dropping to the alloy
  # user, so the rendered file stays root-only.
  sops.secrets.OTEL_INGEST_TOKEN = { };

  sops.templates."alloy-env" = {
    content = ''
      OTEL_INGEST_TOKEN=${config.sops.placeholder.OTEL_INGEST_TOKEN}
    '';
    restartUnits = [ "alloy.service" ];
  };

  systemd.services.alloy.serviceConfig.EnvironmentFile = config.sops.templates."alloy-env".path;

  # public front door for third-party telemetry (OpenRouter broadcast).
  # x-expose drops the tailnet guard, so the routing is what keeps the surface
  # at one path: only the OTLP traces endpoint is proxied, everything else 404s.
  services.caddy.virtualHosts."otel.alper-celik.dev" = {
    x-expose = true;

    extraConfig = ''
      @otlp path /v1/traces
      handle @otlp {
        reverse_proxy http://127.0.0.1:4320
      }
      handle {
        respond 404
      }
    '';
  };
}
