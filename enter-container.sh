#!/bin/bash
# Helper script to enter the NixOS development container

# Get the directory name for unique container naming
export COMPOSE_PROJECT_NAME=$(basename "$PWD")

if ! docker ps | grep -q "nixos-dev-${COMPOSE_PROJECT_NAME}"; then
    echo "Container is not running. Starting it..."
    docker compose up -d
    sleep 2
fi

echo "Entering NixOS development container..."
docker compose exec --user dev nixos-dev /nix/var/nix/profiles/default/bin/bash -c "source ~/.bashrc && exec bash -i"
