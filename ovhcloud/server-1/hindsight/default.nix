# Hindsight memory server: one shared memory bank for Hermes (hetzner) and omp (laptop).
{
  imports = [
    ./postgres.nix
    ./container.nix
    ./secrets.nix
    ./networking.nix
  ];

  # Port shared by the container (container.nix) and the tailnet firewall rule
  # (networking.nix), declared once here and handed to both as module args.
  _module.args.hindsightPorts = {
    api = 21912; # Hindsight REST API + MCP (/mcp)
  };
}
