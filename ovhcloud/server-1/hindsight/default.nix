# Hindsight memory server (shared memory bank for Hermes + omp).
#
# Architecture (agreed with Alper, 2026-09):
#   - One Hindsight instance in a podman container (`latest-slim` image, x86_64),
#     storing into the host PostgreSQL 18 via pgvector.
#   - No local ML: LLM (extraction/reflect), embeddings (qwen3-embedding-8b) and
#     reranking all go through OpenRouter; reranker uses `rrf` (no model at all).
#   - DB access over the postgres UNIX socket with peer auth — no TCP listener,
#     no password, no pg_hba change. This works because the container runs with
#     the same UID as the host user `hindsight` (postgres resolves the socket
#     peer's UID to the HOST passwd; pg_hba default `local all all peer` matches
#     the role of the same name created by `ensureUsers`).
#   - `/run/postgresql` is a RuntimeDirectory: recreated (new inode) on every
#     postgres restart, which would leave a bind-mounted copy stale. We give
#     postgres a second, persistent socket dir instead and mount that.
#   - Exposed tailnet-only (firewall): hetzner Hermes, the laptop (omp) and any
#     MCP client (Hindsight serves MCP at /mcp) connect over tailscale.
#   - OpenRouter key arrives via sops `hindsight_env` (env-file secret, same
#     shape as `audiomuse_env` on rpi5) — see secrets.nix for the contents.
#
# Layout mirrors hetzner/server-1/hermes/ (folder module; the flake's all-file
# resolves the directory to this default.nix):
#   postgres.nix   pgvector, db/role, socket dirs
#   container.nix  host user + the podman container
#   secrets.nix    sops secret
#   networking.nix firewall
{
  imports = [
    ./postgres.nix
    ./container.nix
    ./secrets.nix
    ./networking.nix
  ];

  # Port shared by the container (container.nix) and the firewall rule
  # (networking.nix), declared once here and handed to both as module args.
  _module.args.hindsightPorts = {
    api = 8888; # Hindsight REST API + MCP (/mcp)
  };
}
