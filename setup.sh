#!/bin/bash
# Setup script for NixOS development container

set -e

echo "🚀 Setting up NixOS development container"
echo ""

# Get the directory name for unique container naming
export COMPOSE_PROJECT_NAME=$(basename "$PWD")

# Get Docker group ID
DOCKER_GID=$(getent group docker | cut -d: -f3)
echo "Docker GID: $DOCKER_GID"
echo "Project name: $COMPOSE_PROJECT_NAME"

# Create .env file with Docker GID and project name
cat > .env << EOF
DOCKER_GID=$DOCKER_GID
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
EOF
echo "✅ Created .env file"
echo ""

# Create workspace directory
mkdir -p workspace
echo "✅ Created workspace directory"
echo ""

# Build the container
echo "🔨 Building NixOS development container..."
docker compose build

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
