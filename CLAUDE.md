# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@../AGENTS.md

## What Is Ghaf

Ghaf Framework is a Nix Flakes-based security framework that compartmentalizes applications into isolated VMs on edge devices. Targets x86_64 (laptops) and aarch64 (NVIDIA Jetson Orin). Built entirely with NixOS modules composed via flake-parts.

## Build Commands

All builds use Nix. No Makefile. Nix is available inside the Docker Compose `nixos-dev` service (see AGENTS.md for container usage).

```bash
# Enter devshell (provides treefmt, reuse, nix-fast-build, etc.)
nix develop

# Format check (pre-commit runs this automatically)
nix fmt -- --fail-on-change

# License compliance
nix develop --command reuse lint

# Build pre-commit checks (CI parity)
nix build .#checks.x86_64-linux.pre-commit

# Evaluate all outputs (catches module errors without building)
nix flake show --all-systems

# Build a specific target
nix build .#generic-x86_64-debug
nix build .#nvidia-jetson-orin-agx-debug
nix build .#nvidia-jetson-orin-agx-debug-from-x86_64          # cross-compiled image
nix build .#nvidia-jetson-orin-agx-debug-from-x86_64-flash-script  # flash script

# Build docs
nix build .#doc
```

Builds are slow (45 min to 3+ hours). Use `ghaf-dev.cachix.org` substituter (configured in flake.nix). Never cancel long-running builds.

## Architecture

```
flake.nix                          # Top-level: inputs, nixConfig, flake-parts imports
├── lib/builders/                  # mkGhafConfiguration, mkGhafInstaller — core builders
│   └── mkGhafConfiguration.nix   #   Takes: name, system, profile, hardwareModule, variant, extraModules, vmConfig
├── lib/default.nix                # Extends nixpkgs.lib with ghaf types (globalConfig, networking, policy)
├── lib/global-config.nix          # Debug/release/minimal profile definitions
├── modules/flake-module.nix       # Imports all NixOS modules under ghaf.* namespace
│   ├── common/                    #   Shared: networking, firewall, security, users, logging
│   ├── microvm/                   #   VM base configs: guivm, netvm, audiovm, etc.
│   ├── hardware/                  #   Hardware abstractions
│   ├── profiles/                  #   System profiles (debug, release, laptop-x86, orin)
│   ├── reference/                 #   Reference hardware implementations
│   ├── givc/                      #   Inter-VM communication
│   └── desktop/                   #   Desktop environment configs
├── targets/                       # Hardware targets using mkGhafConfiguration
│   ├── laptop/flake-module.nix    #   x86 laptops (Lenovo, Dell, System76, Alienware)
│   ├── nvidia-jetson-orin/        #   Jetson Orin AGX/NX targets
│   └── generic-x86_64/           #   Generic x86 debug/release
├── packages/                      # Custom packages (pkgs-by-name/ structure)
├── overlays/                      # Cross-compilation and package fix overlays
├── nix/                           # devshell, treefmt, pre-commit hooks, nixpkgs settings
└── tests/                         # Flake checks (installer, logging, firewall)
```

### Composition Pattern

Targets use `mkGhafConfiguration` which takes a hardware module + profile + extra modules and produces a NixOS configuration with VM compartments. Each target's `flake-module.nix` exports `packages` and `nixosConfigurations`.

Options live under `ghaf.*` namespace. Use `lib.mkEnableOption` for feature flags, `lib.mkIf` for conditional config, `lib.mkDefault` for overridable defaults.

VM configurations use `globalConfig` and `hostConfig` patterns for cross-VM data sharing.

## Formatting and Linting

Treefmt handles all formatting (runs via pre-commit hook on `git commit`):
- **Nix**: nixfmt (RFC 166), deadnix, statix
- **Python**: ruff
- **Bash**: shellcheck, shfmt
- **JS**: prettier
- **GitHub Actions**: actionlint

## File Conventions

- SPDX headers required on all new files:
  ```nix
  # SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
  # SPDX-License-Identifier: Apache-2.0
  ```
  (Use `CC-BY-SA-4.0` for documentation files)
- Include `_file = ./<filename>.nix;` in NixOS modules for better eval traces
- File names: kebab-case (`feature-name.nix`)
- Commit messages: Linux-kernel-style imperative subject, optional body explaining what/why

## Key Flake Inputs

- `nixpkgs` (nixos-unstable), `flake-parts`, `jetpack-nixos` (Orin support)
- `ghafpkgs` (Ghaf-specific packages), `givc` (inter-VM communication)
- `microvm` (VM infrastructure), `disko` (disk partitioning)

## Validation Workflow

Smallest set that catches regressions for your change:
1. `nix fmt -- --fail-on-change` — always
2. `nix develop --command reuse lint` — always for new/renamed files
3. `nix flake show --all-systems` — for module/target/flake changes
4. `nix build .#checks.x86_64-linux.pre-commit` — CI parity
5. Target-specific build — when touching hardware/target code
