# NixOS Development Container

Run a full NixOS environment inside Docker. Perfect for developing Nix-based projects while keeping your host system clean.

## 🎯 What You Get

- **Full Nix environment** with flakes enabled
- **Docker access** via host's Docker daemon (no Docker-in-Docker overhead)
- **Persistent storage** for Nix store and home directory
- **Shared workspace** directory between host and container
- **Pre-configured** with common development tools

## 📋 Prerequisites

- Linux system with Docker installed
- At least 10GB free disk space
- Internet connection for downloading packages
- KVM support (for virtualization features)

## 🚀 Quick Start

### 1. Run the setup script

```bash
chmod +x setup.sh
./setup.sh
```

This will:
- Install Docker (if not already installed)
- Create necessary directories
- Build the NixOS container
- Configure Docker socket access

### 2. Start the container

```bash
docker compose up -d
```

### 3. Enter the container

```bash
./enter-container.sh
```

Or manually:
```bash
docker compose exec nixos-dev bash
```

## 📁 Project Structure

```
.
├── Dockerfile              # Container definition
├── docker-compose.yml      # Container orchestration
├── flake.nix              # Nix flake for development
├── setup.sh               # Setup script
├── enter-container.sh     # Quick entry script
├── manage-container.sh    # Container management
├── workspace/             # Shared workspace (your projects go here)
└── README.md              # This file
```

## 🛠️ Usage

### Working with Nix Projects

Inside the container:

```bash
# Navigate to workspace
cd /workspace

# Clone your project
git clone https://github.com/your/nix-project.git
cd nix-project

# Use nix-shell (legacy)
nix-shell

# Or use flakes (modern)
nix develop

# Build the project
nix build

# Run the project
nix run
```

### Using Docker from Inside the Container

The container has access to your host's Docker daemon:

```bash
# Check Docker status
docker ps

# Run containers
docker run hello-world

# Use docker-compose
docker-compose up -d
```

### Development Workflows

#### Python Project
```bash
cd /workspace
nix-shell -p python311 python311Packages.pip
```

#### Node.js Project
```bash
cd /workspace
nix-shell -p nodejs_20 nodePackages.npm
```

#### Rust Project
```bash
cd /workspace
nix-shell -p rustc cargo
```

#### Custom Environment with flake.nix
```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  
  outputs = { nixpkgs, ... }: {
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
        nodejs_20
        python311
        rustc
        cargo
      ];
    };
  };
}
```

Then: `nix develop`

## 🔧 Container Management

Use the management script:

```bash
./manage-container.sh status    # Check container status
./manage-container.sh stop      # Stop the container
./manage-container.sh restart   # Restart the container
./manage-container.sh logs      # View container logs
./manage-container.sh rebuild   # Rebuild from scratch
./manage-container.sh clean     # Remove container and volumes
```

Or use docker compose directly:

```bash
docker compose up -d           # Start in background
docker compose down            # Stop and remove
docker compose ps              # Show status
docker compose logs -f         # Follow logs
docker compose exec nixos-dev bash  # Enter container
```

## 📦 Installed Tools

### Nix Tools
- `nix` - Nix package manager with flakes
- `nix-prefetch-git` - Fetch git repositories
- `nixpkgs-fmt` - Format Nix code
- `alejandra` - Alternative Nix formatter
- `nil` - Nix LSP server
- `direnv` - Automatic environment loading

### Development Tools
- `git`, `gh` - Version control and GitHub CLI
- `vim`, `neovim` - Text editors
- `bash` - Interactive shell
- `gcc`, `make`, `cmake`, `pkg-config` - Build tools
- `jq`, `yq-go` - JSON/YAML processors
- `htop`, `tree` - System utilities
- `tmux` - Terminal multiplexer
- `fzf`, `ripgrep`, `fd`, `bat`, `eza` - Modern shell utilities

### Docker Tools
- `docker-client` - Docker CLI
- `docker-compose` - Container orchestration

## 🔍 Troubleshooting

### Docker Permission Denied

If you get permission errors:

```bash
# Add yourself to docker group
sudo usermod -aG docker $USER

# Apply changes
newgrp docker

# Or log out and back in
```

### Container Won't Start

Check logs:
```bash
docker compose logs
```

Rebuild:
```bash
./manage-container.sh rebuild
```

### Nix Store Full

Clean up old generations:
```bash
# Inside container
nix-collect-garbage -d
```

### Docker Socket Not Accessible

Check that `/var/run/docker.sock` exists on host and is accessible:
```bash
ls -la /var/run/docker.sock
```

Make sure Docker is running:
```bash
sudo systemctl status docker
```

### Port Already in Use

Edit `docker-compose.yml` and change the conflicting port:
```yaml
ports:
  - "2222:22"    # Change first number to available port
  - "8080:8080"
  - "3000:3000"
  - "5000:5000"
  - "8000:8000"
```

## 💡 Tips & Best Practices

### 1. Persist Your Work

Always work in `/workspace` - it's mounted from your host and persists across container restarts.

### 2. Use Nix Flakes

Modern Nix projects should use flakes:

```bash
nix flake init
nix flake update
nix develop
```

### 3. Keep Nix Store Clean

Regularly run garbage collection:
```bash
nix-collect-garbage -d
```

### 4. Version Control

The workspace directory is perfect for your git repositories:
```bash
cd /workspace
git clone your-repo
```

### 5. Share Configuration

Keep your `flake.nix` in your project repository so team members can reproduce your environment.

### 6. IDE Integration

#### VS Code
Install the "Remote - Containers" extension and attach to the running container.

#### Vim/Neovim
The container includes vim and neovim. Configure `nil` (Nix LSP) for IDE features.

### 7. Custom Packages

Add packages to your shell without rebuilding:
```bash
nix-shell -p postgresql nodejs python311
```

### 8. Use direnv for Auto-Loading

Create a `.envrc` file in your project:
```bash
use flake
```

Then allow it:
```bash
direnv allow
```

Now the environment loads automatically when you `cd` into the directory!

### 9. Docker from Inside Container

Remember you're using the host's Docker, so containers you create will run on the host:
```bash
docker run -d nginx  # Runs on host, not in NixOS container
```

## 🌐 Accessing Services

Services running in the container are accessible from your host:

- Port 2222: SSH (if enabled)
- Port 8080: `http://localhost:8080`
- Port 3000: `http://localhost:3000`
- Port 5000: `http://localhost:5000`
- Port 8000: `http://localhost:8000`

Add more ports in `docker-compose.yml` as needed.

## 🔄 Updating

### Update Nix Packages

Inside the container:
```bash
nix-channel --update
```

Or with flakes:
```bash
nix flake update
```

### Rebuild Container

```bash
./manage-container.sh rebuild
```

## 📚 Resources

- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [NixOS Wiki](https://nixos.wiki/)
- [Zero to Nix](https://zero-to-nix.com/)

## 🆘 Getting Help

If you encounter issues:

1. Check the logs: `docker compose logs`
2. Verify Docker is running: `sudo systemctl status docker`
3. Check container status: `./manage-container.sh status`
4. Try rebuilding: `./manage-container.sh rebuild`

## 🧹 Cleanup

To completely remove everything:

```bash
# Stop and remove container
docker compose down

# Remove volumes (Nix store and home)
docker volume rm $(docker volume ls -q | grep nixos)

# Remove Docker images
docker rmi nixos-dev_nixos-dev nixos/nix:latest
```

## 📝 Notes

- The Nix store and home directory persist in Docker volumes
- The workspace directory is mounted from your host
- Docker socket is mounted for host Docker access
- Container runs as the `dev` user (UID 1000)
- Uses `nixos/nix:2.19.2` base image for stability
- Includes health checks to monitor nix-daemon status
- `direnv` is pre-configured in `.bashrc` for automatic environment loading
- SSH keys are mounted read-only for git authentication
- KVM device is mounted for virtualization support (requires privileged mode)
- Uses NixOS 24.05 channel by default
- Container name and hostname can be customized via `COMPOSE_PROJECT_NAME` environment variable

## 🎉 Happy Nixing!

You now have a fully functional NixOS environment in Docker. Build reproducible projects, experiment with Nix, and keep your host system clean!
