{
  lib,
  config,
  inputs,
  ...
}:
let
  secrets = inputs.MyServersSecrets;
in
{
  sops.secrets = {
    CF_DNS_API_TOKEN = {
      sopsFile = "${secrets}/secrets/common.yaml";
      format = "yaml";
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      profile = "shortlived";
      email = "alper@alper-celik.dev";
      renewInterval = "6h";
      renewJitter = "2h";
      validMinDays = 4;
      dnsProvider = "cloudflare";
      credentialFiles = {
        CF_DNS_API_TOKEN_FILE = config.sops.secrets.CF_DNS_API_TOKEN.path;
      };
    };
  };
  security.acme.certs = builtins.mapAttrs (_: vhost: {
    domain = vhost.hostName;
    extraDomainNames = vhost.serverAliases;
  }) config.services.caddy.virtualHosts;

}
