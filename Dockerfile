FROM nixos/nix:2.19.2

# Enable flakes and nix-command (need to replace symlink with real file)
RUN cp /etc/nix/nix.conf /etc/nix/nix.conf.tmp && \
    rm /etc/nix/nix.conf && \
    mv /etc/nix/nix.conf.tmp /etc/nix/nix.conf && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Fix Nix store permissions for multi-user installation
RUN chown -R root:root /nix/store /nix/var && \
    chmod 1775 /nix/store && \
    mkdir -p /nix/var/nix/profiles/per-user && \
    mkdir -p /nix/var/nix/gcroots/per-user


# Install additional packages (base image already has bash, git, openssh, coreutils)
RUN nix profile install --profile /nix/var/nix/profiles/default \
    nixpkgs#util-linux \
    nixpkgs#shadow \
    nixpkgs#vim \
    nixpkgs#htop \
    nixpkgs#tree \
    nixpkgs#jq \
    nixpkgs#gnumake \
    nixpkgs#gcc \
    nixpkgs#pkg-config \
    nixpkgs#docker-client \
    nixpkgs#nix-prefetch-git \
    nixpkgs#nixpkgs-fmt \
    nixpkgs#nil \
    nixpkgs#alejandra \
    nixpkgs#gnused \
    nixpkgs#ripgrep \
    nixpkgs#gawk \
    nixpkgs#sudo \
    nixpkgs#linux-pam \
    nixpkgs#direnv

# Ensure sudo is setuid root inside the Nix store
RUN SUDO_BIN="$(readlink -f /nix/var/nix/profiles/default/bin/sudo)" && \
    chown root:root "$SUDO_BIN" && \
    chmod 4755 "$SUDO_BIN"


# Set up a development user (minimal image doesn't have adduser/addgroup)
# Need to replace symlinks with actual files since /etc/passwd is read-only in nix store
RUN mkdir -p /home/dev/.config/nix && \
    cp /etc/passwd /etc/passwd.tmp && rm /etc/passwd && mv /etc/passwd.tmp /etc/passwd && \
    cp /etc/group /etc/group.tmp && rm /etc/group && mv /etc/group.tmp /etc/group && \
    echo "dev:x:1000:1000:Developer:/home/dev:/nix/var/nix/profiles/default/bin/bash" >> /etc/passwd && \
    echo "dev:x:1000:" >> /etc/group

# Allow dev to use sudo without a password
RUN mkdir -p /etc/sudoers.d && \
    echo "Defaults secure_path=/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/usr/bin:/bin" > /etc/sudoers && \
    echo "Defaults env_reset" >> /etc/sudoers && \
    echo "#includedir /etc/sudoers.d" >> /etc/sudoers && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers && \
    chmod 0440 /etc/sudoers.d/dev

# Minimal PAM config for sudo (allow all inside container)
RUN mkdir -p /etc/pam.d /lib && \
    ln -s /nix/var/nix/profiles/default/lib/security /lib/security && \
    printf 'auth    sufficient pam_permit.so\naccount sufficient pam_permit.so\nsession sufficient pam_permit.so\n' > /etc/pam.d/sudo

# Create per-user Nix directories
RUN mkdir -p /nix/var/nix/profiles/per-user/dev && \
    mkdir -p /nix/var/nix/gcroots/per-user/dev && \
    chown -R dev:dev /nix/var/nix/profiles/per-user/dev && \
    chown -R dev:dev /nix/var/nix/gcroots/per-user/dev

# Create common directories and set ownership
RUN mkdir -p /workspace && \
    chown -R dev:dev /workspace /home/dev

# Configure Nix for the dev user - enable trusted users
# Must be set before daemon starts, and daemon must recognize UID 1000
RUN echo "experimental-features = nix-command flakes" > /home/dev/.config/nix/nix.conf && \
    chown dev:dev /home/dev/.config/nix/nix.conf && \
    echo "trusted-users = root dev" >> /etc/nix/nix.conf

# Set up direnv and custom prompt for automatic environment loading
RUN echo 'eval "$(direnv hook bash)"' >> /home/dev/.bashrc && \
    echo 'export PS1="[\u@nixos-dev \W]\\$ "' >> /home/dev/.bashrc && \
    chown dev:dev /home/dev/.bashrc

# Create a startup script with proper signal handling
RUN printf '#!/nix/var/nix/profiles/default/bin/bash\n\
set -e\n\
\n\
# Function for graceful shutdown\n\
shutdown() {\n\
    echo "Shutting down..."\n\
    kill -TERM $NIX_DAEMON_PID 2>/dev/null || true\n\
    exit 0\n\
}\n\
\n\
# Trap signals for graceful shutdown\n\
trap shutdown SIGTERM SIGINT\n\
\n\
echo "Starting Nix daemon..."\n\
export HOME=/root\n\
nix-daemon &\n\
NIX_DAEMON_PID=$!\n\
sleep 2\n\
\n\
echo "Nix daemon started (PID: $NIX_DAEMON_PID)"\n\
echo "Switching to dev user..."\n\
\n\
# Switch to dev user environment and keep container running\n\
cd /workspace\n\
export HOME=/home/dev\n\
export USER=dev\n\
export PATH=/nix/var/nix/profiles/default/bin:$PATH\n\
\n\
# Run interactive bash as dev user - use tail -f to keep container alive\n\
exec /nix/var/nix/profiles/default/bin/tail -f /dev/null\n' > /start.sh && \
    chmod +x /start.sh

# Set up environment
ENV USER=dev
ENV HOME=/home/dev
ENV PATH=/nix/var/nix/profiles/default/bin:$PATH
WORKDIR /workspace

# Run as root to start daemon, then switch to dev user
CMD ["/start.sh"]
