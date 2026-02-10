# Agent Instructions

- Nix is available inside the Docker Compose service, not directly on the host.
- Use the `nixos-dev` service and run commands as user `dev`.
- Start the container before running Nix commands:
  - `docker compose up -d`
- Execute Nix commands through Compose:
  - `docker compose exec --user dev nixos-dev bash -lc "nix --version"`
  - `docker compose exec --user dev nixos-dev bash -lc "nix develop"`
  - `docker compose exec --user dev nixos-dev bash -lc "nix build"`
- Project files are mounted at `/workspace` inside the container.
