{ config, ... }:
{
  # services.nginx.virtualHosts."id.lab.alper-celik.dev" = {
  #   forceSSL = true;
  #   enableACME = true;
  #   acmeRoot = null;
  #   expose = true;
  #   locations = {
  #     "/" = {
  #       proxyPass = "http://localhost:${toString config.services.keycloak.settings.http-port}";
  #       extraConfig = ''
  #         proxy_set_header    Host               $host;
  #         proxy_set_header    X-Real-IP          $remote_addr;
  #         proxy_set_header    X-Forwarded-For    $proxy_add_x_forwarded_for;
  #         proxy_set_header    X-Forwarded-Host   $host;
  #         proxy_set_header    X-Forwarded-Server $host;
  #         proxy_set_header    X-Forwarded-Port   $server_port;
  #         proxy_set_header    X-Forwarded-Proto  $scheme;
  #       '';
  #     };
  #   };
  # };
  #
  # services.keycloak = {
  #   enable = true;
  #   database = {
  #     type = "postgresql";
  #     passwordFile = config.sops.secrets."postgres/keycloak-pass".path;
  #     createLocally = true;
  #   };
  #   settings = {
  #     hostname = "id.lab.alper-celik.dev";
  #     proxy-headers = "xforwarded";
  #     hostname-port = 443;
  #     http-port = 38080;
  #     http-enabled = true;
  #   };
  #
  # };
}
