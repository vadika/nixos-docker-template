#!/bin/bash
# Helper scripts for NixOS container management

set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export COMPOSE_PROJECT_NAME="$(basename "$SCRIPT_DIR")"
COMPOSE_CMD=(docker compose --project-directory "$SCRIPT_DIR")

# Stop the container
stop-container() {
    echo "Stopping NixOS development container..."
    "${COMPOSE_CMD[@]}" down
}

# Restart the container
restart-container() {
    echo "Restarting NixOS development container..."
    "${COMPOSE_CMD[@]}" restart
}

# View container logs
logs-container() {
    "${COMPOSE_CMD[@]}" logs -f
}

# Clean up (removes container and volumes)
clean-container() {
    echo "⚠️  This will remove the container and all volumes (including Nix store)"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "${COMPOSE_CMD[@]}" down -v
        echo "✅ Container and volumes removed"
    fi
}

# Rebuild the container
rebuild-container() {
    echo "Rebuilding NixOS development container..."
    "${COMPOSE_CMD[@]}" build --no-cache
    "${COMPOSE_CMD[@]}" up -d
}

# Show container status
status-container() {
    "${COMPOSE_CMD[@]}" ps
    echo ""
    echo "Docker socket accessible:"
    "${COMPOSE_CMD[@]}" exec nixos-dev docker ps &>/dev/null && echo "✅ Yes" || echo "❌ No"
    echo "Container name: nixos-dev-${COMPOSE_PROJECT_NAME}"
}

# Parse command
case "$1" in
    stop)
        stop-container
        ;;
    restart)
        restart-container
        ;;
    logs)
        logs-container
        ;;
    clean)
        clean-container
        ;;
    rebuild)
        rebuild-container
        ;;
    status)
        status-container
        ;;
    *)
        echo "NixOS Container Management"
        echo ""
        echo "Usage: $0 {stop|restart|logs|clean|rebuild|status}"
        echo ""
        echo "Commands:"
        echo "  stop    - Stop the container"
        echo "  restart - Restart the container"
        echo "  logs    - View container logs"
        echo "  clean   - Remove container and volumes"
        echo "  rebuild - Rebuild container from scratch"
        echo "  status  - Show container status"
        exit 1
        ;;
esac
