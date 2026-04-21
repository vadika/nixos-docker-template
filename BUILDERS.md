# Remote Nix Builder Setup

This guide covers configuration for the `artemis2` remote Nix builder and binary cache used by the development container.

## Architecture

- **Host**: `artemis2` (Ubuntu 24.04, x86_64, reached over Tailscale MagicDNS).
- **Builder**: `nix-daemon` on artemis2, accessed via `ssh-ng://vadikas@artemis2`. Build dispatch only; no aarch64 builder is configured.
- **Binary cache**: `nix-serve-ng` on `http://artemis2:5000` (systemd unit `nix-serve.service`), signing key at `/var/cache/nix-binary-cache/secret-key`.
- **Public key** (pinned as `extra-trusted-public-keys` in the Dockerfile):
  ```
  artemis2-cache-1:O8uCygBXRmiHCpr5MjpWSV9bjPrw9YXHawfAJDag3bU=
  ```

To rotate the key: regenerate on artemis2 with `nix-store --generate-binary-cache-key artemis2-cache-1 /var/cache/nix-binary-cache/secret-key /var/cache/nix-binary-cache/public-key`, restart `nix-serve.service`, then update `extra-trusted-public-keys` in the Dockerfile and rebuild the image.

## SSH Connection Multiplexing

Nix opens many SSH connections to remote builders during a single build. Without multiplexing, each connection performs a full handshake including post-quantum key exchange (`sntrup761x25519-sha512`), which takes ~4 seconds per connection. This adds significant overhead to builds.

SSH multiplexing keeps a persistent master connection and reuses it for subsequent sessions, reducing per-connection overhead from ~4s to ~8ms.

### Setup

Add the following to your `~/.ssh/config` on the **host machine** (it is bind-mounted read-only into the container):

```
Host artemis2
  User vadikas
  ControlMaster auto
  ControlPath /tmp/.ssh-sockets/%r@%h-%p
  ControlPersist 600
  ServerAliveInterval 15
  ServerAliveCountMax 3
```

Key points:

- **ControlPath must use a writable location inside the container.** The host `~/.ssh` is mounted read-only at `/home/dev/.ssh`, so `~/.ssh/sockets/` will not work. Use `/tmp/.ssh-sockets/` instead.
- **ControlPersist 600** keeps the master connection alive for 10 minutes after the last session closes, covering typical build gaps.
- The socket directory must exist before the first connection. `/start.sh` recreates it on each container start since `/tmp` is ephemeral.

### Verification

From inside the container:

```bash
# First connection (~4s, establishes master)
time ssh vadikas@artemis2 echo "connected"

# Second connection (~0.01s, reuses master)
time ssh vadikas@artemis2 echo "connected"

# Cache health
curl -sS http://artemis2:5000/nix-cache-info
```

To check the master connection status:

```bash
ssh -O check vadikas@artemis2
```

To manually close it:

```bash
ssh -O exit vadikas@artemis2
```

### Why This Matters

A single `nix build` to a remote builder can open dozens of SSH connections (store path queries, build dispatches, result copies). At 4 seconds each, this adds minutes of pure SSH overhead. With multiplexing, only the first connection pays the handshake cost.

## Cross-Compilation Cache Misses

When building aarch64 targets from x86_64 (the `-from-x86_64` variants in Ghaf), some derivations will not be found in the NixOS binary cache (`cache.nixos.org`). This is expected. There is no dedicated aarch64 builder — aarch64 output is produced via the cross-compilation overlay on artemis2.

### Why

Ghaf applies a cross-compilation overlay (`overlays/cross-compilation/default.nix`) that modifies several packages. Any overlay applied to nixpkgs changes the fixed-point evaluation, which alters derivation hashes for the entire dependency tree. Even packages not directly modified by the overlay get different store paths than what Hydra built.

The `ghaf-dev.cachix.org` cache will have these if CI has built them; `cache.nixos.org` only has "vanilla" nixpkgs derivations. Paths built locally on artemis2 land in its `nix-serve-ng` cache, so a second developer pulling from `http://artemis2:5000` gets them for free.

If you notice unexpected packages being built from source, trace the dependency chain with:

```bash
nix why-depends --derivation \
  .#packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64 \
  /nix/store/<hash>-<package>.drv
```

## Operational Notes (artemis2)

- nix-serve binary: `/nix/var/nix/profiles/nix-serve/bin/nix-serve` (nix-serve-ng, installed via `nix profile install --profile /nix/var/nix/profiles/nix-serve nixpkgs#nix-serve-ng`).
- Systemd unit: `/etc/systemd/system/nix-serve.service`. Logs: `journalctl -u nix-serve -f`.
- `trusted-users = root vadikas` is set in `/etc/nix/nix.custom.conf` (Determinate Nix rewrites `/etc/nix/nix.conf`, so user overrides must live in `nix.custom.conf`). Restart `nix-daemon.service` after changes.
- Firewall: host-level firewall is inactive; tailnet-only exposure is expected. If you ever enable ufw, allow tcp/5000 on the tailnet interface only.
