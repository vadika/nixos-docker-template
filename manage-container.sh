#!/bin/bash
# Helper scripts for NixOS container management

# Get the directory name for unique container naming
export COMPOSE_PROJECT_NAME=$(basename "$PWD")

# Stop the container
stop-container() {
    echo "Stopping NixOS development container..."
    docker compose down
}

# Restart the container
restart-container() {
    echo "Restarting NixOS development container..."
    docker compose restart
}

# View container logs
logs-container() {
    docker compose logs -f
}

# Clean up (removes container and volumes)
clean-container() {
    echo "⚠️  This will remove the container and all volumes (including Nix store)"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose down -v
        echo "✅ Container and volumes removed"
    fi
}

# Rebuild the container
rebuild-container() {
    echo "Rebuilding NixOS development container..."
    docker compose build --no-cache
    docker compose up -d
}

# Show container status
status-container() {
    docker compose ps
    echo ""
    echo "Docker socket accessible:"
    docker compose exec nixos-dev docker ps &>/dev/null && echo "✅ Yes" || echo "❌ No"
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
