#!/bin/bash
# Setup script for NixOS development container

set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="$(basename "$SCRIPT_DIR")"
WORKSPACE_DIR="$SCRIPT_DIR/workspace"

echo "🚀 Setting up NixOS development container"
echo ""

# Get the directory name for unique container naming
export COMPOSE_PROJECT_NAME="$PROJECT_NAME"

# Get Docker group ID
DOCKER_GID=$(getent group docker | cut -d: -f3)
echo "Docker GID: $DOCKER_GID"
echo "Project name: $COMPOSE_PROJECT_NAME"

# Create .env file with Docker GID and project name
cat > "$SCRIPT_DIR/.env" << EOF
DOCKER_GID=$DOCKER_GID
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
WORKSPACE_DIR=$WORKSPACE_DIR
EOF
echo "✅ Created .env file"
echo ""

# Create workspace directory
mkdir -p "$WORKSPACE_DIR"
echo "✅ Created workspace directory"
echo ""

# Build the container
echo "🔨 Building NixOS development container..."
docker compose --project-directory "$SCRIPT_DIR" build

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the container, run:"
echo "  docker compose up -d"
echo ""
echo "To enter the container, run:"
echo "  docker compose exec nixos-dev bash"
echo ""
echo "Or use the helper script:"
echo "  ./enter-container.sh"
echo ""
