# Tailnet-only exposure for the hindsight API/MCP.
{ hindsightPorts, ... }:
{
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ hindsightPorts.api ];
}
