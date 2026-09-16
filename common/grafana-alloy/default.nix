{ lib, config, ... }:
# lib.mkIf config.services.alloy.enable
let
  mkIfArr = cond: val: if cond then val else [ ];
in
lib.mkIf config.services.alloy.enable {

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 12345 ];
  users = {
    users.alloy = {
      isSystemUser = true;
      group = "alloy";
      extraGroups = [
        "messagebus"

        # for journal see https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/
        "adm"
        "systemd-journal"
      ]
      ++ mkIfArr config.services.nginx.enable [ "nginx" ];
    };
    groups.alloy = { };
  };

  systemd.services.alloy.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "alloy";
    Group = "alloy";
  };

  # Default OTLP export settings for every systemd unit on this host.
  # Apps with an OTel SDK pick these up automatically; others ignore them.
  # host/arch attribution happens in Alloy (otelcol.alloy relabels), so no
  # OTEL_RESOURCE_ATTRIBUTES needed here.
  systemd.settings.Manager = {
      DefaultEnvironment = [
        "OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318"
        "OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"
      ];
    };

}
