#!/bin/bash
# Helper script to enter the NixOS development container

set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_CMD=(docker compose --project-directory "$SCRIPT_DIR")

if ! "${COMPOSE_CMD[@]}" ps --status running --services | grep -q '^nixos-dev$'; then
    echo "Container is not running. Starting it..."
    "${COMPOSE_CMD[@]}" up -d
    sleep 2
fi

echo "Entering NixOS development container..."
"${COMPOSE_CMD[@]}" exec --user dev nixos-dev /nix/var/nix/profiles/default/bin/bash -c "source ~/.bashrc && exec bash -i"
