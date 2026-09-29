# Tailnet-only HTTPS in front of the hindsight API/MCP.
#
# `x-expose` is deliberately left at its default (false), so common/caddy.nix
# keeps answering 403 to every client outside the tailnet and the private
# ranges — this vhost adds a name and a cert, not reachability. The upstream is
# the loopback publish (container.nix); the container's own tailnet address
# stays published for clients that would rather skip TLS.
{ hindsightPorts, ... }:
{
  services.caddy.virtualHosts."hindsight.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString hindsightPorts.api}";
  };
}
