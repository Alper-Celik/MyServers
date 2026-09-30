# Grafana alert rules, file-provisioned: this module hands Grafana the YAML in
# this directory, which the NixOS module links to
# provisioning/alerting/rules.yaml on startup.
#
# Layout (folder module; the flake's `all-file` resolves the directory to this
# default.nix, same as common/grafana-alloy/ and ovhcloud/server-1/hindsight/):
#   default.nix      this wiring
#   alert-rules.yaml the four fleet availability rules, in Grafana's own
#                    provisioning format
#
# Why a YAML file instead of `alerting.rules.settings`: the rule set is read and
# reviewed like any other config file (conditions, PromQL, annotations), and it
# can be diffed against what Grafana exports. The folder wrapper is not
# cosmetic: `all-file ./hetzner/server-1` adds every top-level entry as a NixOS
# module, so a bare *.yaml next to observebality-server.nix would be parsed as
# Nix, and a bare directory needs a default.nix to be importable.
#
# Rules are NOT editable in the Grafana UI — change the YAML here and redeploy.
# Routing uses the existing notification policy (Telegram); the `Fleet Alerts`
# folder is created by the alert provisioner on first start.
{ ... }:
{
  services.grafana.provision.alerting.rules.path = ./alert-rules.yaml;
}
