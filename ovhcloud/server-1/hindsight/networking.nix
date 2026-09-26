# Tailnet-only exposure for the hindsight API/MCP (postgres.nix on this host
# opens 5432 on tailscale0 the same way). WAN stays blocked by the default
# firewall — no WAN allow exists anywhere for these ports.
{ hindsightPorts, ... }:
{
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ hindsightPorts.api ];
}
