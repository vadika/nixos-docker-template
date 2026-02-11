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

# Keep critical host-interaction tools available even when /nix is a persisted volume
if ! "${COMPOSE_CMD[@]}" exec nixos-dev bash -lc 'command -v lsusb >/dev/null 2>&1'; then
    echo "Installing missing usbutils (lsusb) in container profile..."
    "${COMPOSE_CMD[@]}" exec nixos-dev bash -lc 'export HOME=/root; nix profile install --profile /nix/var/nix/profiles/default nixpkgs#usbutils'
fi

if ! "${COMPOSE_CMD[@]}" exec nixos-dev bash -lc 'command -v zstd >/dev/null 2>&1'; then
    echo "Installing missing zstd in container profile..."
    "${COMPOSE_CMD[@]}" exec nixos-dev bash -lc 'export HOME=/root; nix profile install --profile /nix/var/nix/profiles/default nixpkgs#zstd'
fi

echo "Entering NixOS development container..."
"${COMPOSE_CMD[@]}" exec --user dev nixos-dev /nix/var/nix/profiles/default/bin/bash -c "source ~/.bashrc && exec bash -i"
