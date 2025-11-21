# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Build System Architecture (Modular)

### Overview

The build system uses a **modular architecture** with `.env` as the single source of truth:

```
.env (config) → Makefile (orchestrator) → Modular Scripts → Generated Files
```

### Directory Structure

```
├── lib/                    # Shared libraries (sourced by scripts)
│   ├── common.sh          # Colors, logging, utilities
│   ├── env-loader.sh      # Environment loading & validation
│   └── proxy-handler.sh   # Proxy configuration logic
├── scripts/               # Functional scripts (executable)
│   ├── setup-env.sh       # Interactive .env creation
│   ├── generate-podmanfile.sh    # Podmanfile generation
│   ├── generate-compose.sh       # Compose file generation
│   ├── build-image.sh            # Container image building
│   └── registry-push.sh          # GHCR push operations
├── Makefile              # Primary orchestrator
├── .env                  # Single source of truth (gitignored)
└── .env.example          # Configuration template
```

### Generated Files (Non-Source)

- [`Podmanfile`](Podmanfile) - **Generated** 3-stage Dockerfile (gitignored)
- [`podman-compose.yml`](podman-compose.yml) - **Generated** compose configuration (gitignored)
- Regenerate after `.env` changes: `make generate-all`

### Build Pipeline

1. **Configuration**: `.env` file loaded by all scripts via [`lib/env-loader.sh`](lib/env-loader.sh)
2. **Orchestration**: [`Makefile`](Makefile) calls modular scripts in sequence
3. **Generation**: Scripts create Podmanfile and compose file from templates
4. **Building**: Podman builds image with proper proxy handling
5. **Publishing**: Optional push to GitHub Container Registry

### Key Scripts

#### Library Scripts (Sourced)
- [`lib/common.sh`](lib/common.sh) - Shared utilities, colors, logging functions
- [`lib/env-loader.sh`](lib/env-loader.sh) - Loads and validates `.env` configuration
- [`lib/proxy-handler.sh`](lib/proxy-handler.sh) - Manages build/runtime proxy configuration

#### Functional Scripts (Executable)
- [`scripts/setup-env.sh`](scripts/setup-env.sh) - Interactive `.env` creation wizard
- [`scripts/generate-podmanfile.sh`](scripts/generate-podmanfile.sh) - Generates 3-stage Podmanfile with conditional proxy support
- [`scripts/generate-compose.sh`](scripts/generate-compose.sh) - Generates podman-compose.yml with volumes and networking
- [`scripts/build-image.sh`](scripts/build-image.sh) - Builds container image with proxy handling
- [`scripts/registry-push.sh`](scripts/registry-push.sh) - Pushes image to ghcr.io (versioned + latest tags)

## Proxy Architecture (Critical)

Two separate proxy configurations with different environment variable names:

### Build-time Proxies
- Variables: `BUILD_HTTP_PROXY`, `BUILD_HTTPS_PROXY`, `BUILD_NO_PROXY`
- Purpose: Affect image creation only (apk, npm during build)
- Controlled by: `USE_BUILD_PROXY` flag in [`.env`](.env)
- Injected: Into Podmanfile as ARG/ENV during image build

### Runtime Proxies
- Variables: `RUNTIME_HTTP_PROXY`, `RUNTIME_HTTPS_PROXY`, `RUNTIME_NO_PROXY`
- Purpose: Affect running container (npm, git commands)
- Controlled by: `USE_RUNTIME_PROXY` flag in [`.env`](.env)
- Configured: By [`entrypoint.sh`](conf/scripts/entrypoint.sh:8-17) on container startup

### Proxy Handling
- [`lib/proxy-handler.sh`](lib/proxy-handler.sh) - Centralizes proxy logic for both build and runtime
- [`scripts/build-image.sh`](scripts/build-image.sh) - Clears environment variables when `USE_BUILD_PROXY=false`

## Volume Mounts (SELinux)

- [`conf/happy/`](conf/happy/) mounted to `/root/.happy` - Happy Coder integration
- [`conf/claude/`](conf/claude/) mounted to `/root/.claude` - Claude Code configuration
- [`workspace/`](workspace/) mounted to `/workspace` - Persistent user data
- All use `:z` SELinux label in compose file for proper file permissions

## Container Behavior

- [`entrypoint.sh`](conf/scripts/entrypoint.sh:35) creates/attaches to tmux session named "main"
- Sessions persist across browser reconnects (tmux detach/attach pattern)
- UTF-8 locale (`LANG=C.UTF-8`, `LC_ALL=C.UTF-8`) for emoji support in Alpine
- ttyd listens on port 7681 inside container, mapped to `TTYD_PORT` on host
- CJK fonts and emoji fonts installed by default for international support

## Workflow Commands

```bash
# Setup and configuration
make setup                  # Interactive .env creation via setup-env.sh

# Build pipeline
make generate-podmanfile    # Generate Podmanfile only
make generate-compose       # Generate podman-compose.yml only
make generate-all           # Generate both files
make build                  # Generate + build image
make rebuild                # Clean + build

# Registry operations
make build-and-push         # Build and push to ghcr.io
make push-to-ghcr           # Push existing image to ghcr.io

# Deployment (recommended: use compose)
make up                     # Start with podman-compose (alias for compose-up)
make down                   # Stop with podman-compose (alias for compose-down)
make compose-restart        # Restart services
make compose-logs           # View logs

# Alternative deployment (direct podman)
make deploy                 # Deploy with podman run (no volumes)
make deploy-with-volume     # Deploy with workspace volume
make stop                   # Stop container only (doesn't remove)
make start                  # Start existing container
make restart                # Restart container

# Maintenance
make clean                  # Remove container + generated files (preserves image)
make clean-all              # Remove container + generated files + image
make prune                  # Remove unused containers and images
make status                 # Show container status and env vars
make logs                   # View container logs
make shell                  # Access container shell
```

## Direct Script Usage

Scripts can be called directly for debugging or custom workflows:

```bash
# Interactive setup
./scripts/setup-env.sh

# Generate files
./scripts/generate-podmanfile.sh
./scripts/generate-compose.sh

# Build and push
./scripts/build-image.sh
./scripts/registry-push.sh      # Requires GHCR configuration
```

## Configuration Management

### Environment Variables (.env)

**Required:**
- `CONTAINER_NAME` - Container/image name
- `TTYD_PORT` - Host port for ttyd web terminal

**Optional Build:**
- `USE_BUILD_PROXY` - Enable build-time proxy (true/false)
- `BUILD_HTTP_PROXY`, `BUILD_HTTPS_PROXY`, `BUILD_NO_PROXY`
- `NODE_VERSION` - Node.js version (default: 24)
- `EXTRA_APK_PACKAGES` - Additional Alpine packages
- `EXTRA_NPM_PACKAGES` - Additional global npm packages

**Optional Runtime:**
- `USE_RUNTIME_PROXY` - Enable runtime proxy (true/false)
- `RUNTIME_HTTP_PROXY`, `RUNTIME_HTTPS_PROXY`, `RUNTIME_NO_PROXY`
- `TTYD_USER`, `TTYD_FONTSIZE` - Terminal customization

**Optional GHCR:**
- `USE_GHCR` - Enable GitHub Container Registry (true/false)
- `GHCR_USERNAME` - GitHub username
- `GHCR_TOKEN` - GitHub personal access token
- `GHCR_TAG` - Version tag (default: git hash or timestamp)

**Optional Claude:**
- `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`

## Registry Tagging Strategy

[`scripts/registry-push.sh`](scripts/registry-push.sh) pushes **two tags**:
1. **Versioned tag**: `ghcr.io/USERNAME/IMAGE:VERSION` (git hash, GHCR_TAG, or timestamp)
2. **Latest tag**: `ghcr.io/USERNAME/IMAGE:latest`

This follows container registry best practices for version tracking.

## Key Differences

### make up vs make deploy

- **`make up`** (compose-up): Uses podman-compose, includes automatic volume mounts, network management
- **`make deploy`**: Direct podman run, simpler but no automatic volumes (use `deploy-with-volume` for volumes)
- **`make down`** (compose-down): Stops and removes containers created by compose
- **`make stop`**: Only stops container, doesn't remove it

### Modular vs Monolithic

**Old (Monolithic):**
- Single [`build.sh`](build.sh.backup) (773 lines) handled everything
- Difficult to test, maintain, and extend
- Mixed concerns: UI, generation, building, pushing

**New (Modular):**
- Separation of concerns: libraries, functional scripts, orchestration
- Independently testable components
- `.env` as single source of truth
- Clear data flow and dependencies