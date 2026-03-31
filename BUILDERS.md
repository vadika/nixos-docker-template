# Remote Nix Builder Setup

This guide covers configuration for remote Nix builders used in the Ghaf development container.

## SSH Connection Multiplexing

Nix opens many SSH connections to remote builders during a single build. Without multiplexing, each connection performs a full handshake including post-quantum key exchange (`sntrup761x25519-sha512`), which takes ~4 seconds per connection. This adds significant overhead to builds.

SSH multiplexing keeps a persistent master connection and reuses it for subsequent sessions, reducing per-connection overhead from ~4s to ~8ms.

### Setup

Add the following to your `~/.ssh/config` on the **host machine** (it is bind-mounted read-only into the container):

```
Host moobe
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
- The socket directory must exist before the first connection. Create it inside the container:
  ```
  mkdir -p /tmp/.ssh-sockets
  ```
  This needs to be done after each container restart since `/tmp` is ephemeral.

### Verification

From inside the container:

```bash
# First connection (~4s, establishes master)
time ssh vadikas@moobe echo "connected"

# Second connection (~0.01s, reuses master)
time ssh vadikas@moobe echo "connected"
```

To check the master connection status:

```bash
ssh -O check vadikas@moobe
```

To manually close it:

```bash
ssh -O exit vadikas@moobe
```

### Why This Matters

A single `nix build` to a remote builder can open dozens of SSH connections (store path queries, build dispatches, result copies). At 4 seconds each, this adds minutes of pure SSH overhead. With multiplexing, only the first connection pays the handshake cost.

## Cross-Compilation Cache Misses

When building aarch64 targets from x86_64 (the `-from-x86_64` variants), some derivations will not be found in the NixOS binary cache (`cache.nixos.org`). This is expected.

### Why

Ghaf applies a cross-compilation overlay (`overlays/cross-compilation/default.nix`) that modifies several packages. Any overlay applied to nixpkgs changes the fixed-point evaluation, which alters derivation hashes for the entire dependency tree. Even packages not directly modified by the overlay get different store paths than what Hydra built.

The `ghaf-dev.cachix.org` cache will have these if CI has built them, but `cache.nixos.org` only has "vanilla" nixpkgs derivations.

### Known Transitive Dependencies

Some unexpected packages appear in the build plan due to transitive dependencies:

| Package | Pulled in by | Reason |
|---------|-------------|--------|
| gfortran | PipeWire -> fftwFloat (fftw-single) | FFTW includes gfortran in `nativeBuildInputs` for Fortran bindings. Not used by Ghaf. Fixed in [PR #1850](https://github.com/tiiuae/ghaf/pull/1850). |

If you notice other unexpected packages being built from source, trace the dependency chain with:

```bash
nix why-depends --derivation \
  .#packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64 \
  /nix/store/<hash>-<package>.drv
```
