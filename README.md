# ttyd Web Terminal Container

A containerized web-based terminal using ttyd on Alpine Linux with Claude Code and Happy Coder integration.

## File Structure

```
.
├── happy-ttyd/
│   └── claude/
│       ├── conf/
│       │   ├── .claude/          # Claude Code configuration and state
│       │   └── .happy/           # Happy Coder configuration and state
│       └── scripts/
│           └── entrypoint.sh     # Container entrypoint script
├── .env                          # Environment configuration (gitignored)
├── .env.example                  # Configuration template
├── .gitignore                    # Git ignore rules
├── build.sh                      # Multi-stage build script with dynamic Podmanfile generation
├── Makefile                      # Build and deployment automation
├── podman-compose.yml            # Container orchestration (generated, gitignored)
└── Podmanfile                    # Container definition (generated, gitignored)
```

## Infrastructure

```mermaid
graph TB
    subgraph "Build Process"
        A[build.sh] -->|generates| B[Podmanfile]
        A -->|generates| C[podman-compose.yml]
        D[.env] -->|configures| A
    end

    subgraph "Container Layers"
        E[alpine:latest<br/>Base Image] --> F[Build Stage<br/>Node.js 24 + npm]
        E --> G[Runtime Stage<br/>ttyd + tmux + tools]
        F -.copy artifacts.-> G
    end

    subgraph "Runtime"
        G --> H[Container<br/>claude_ttyd-terminal_1]
        I[happy-ttyd/claude/scripts/entrypoint.sh] --> H
        J[happy-ttyd/claude/conf/] -.mounted config.-> H
    end

    subgraph "Access"
        H -->|port 7681| K[Web Browser<br/>http://localhost:7681]
    end

    style A fill:#e1f5ff
    style E fill:#fff3e0
    style G fill:#e8f5e9
    style H fill:#f3e5f5
    style K fill:#fce4ec
```

## Quick Start

```bash
# 1. Setup configuration
cp .env.example .env
# Edit .env with your settings

# 2. Build and deploy
make build
make deploy

# 3. Access terminal
# Open http://localhost:7681 in your browser
```

## Container Management

```bash
# Using podman-compose
make compose-up      # Start services
make compose-down    # Stop services
make compose-logs    # View logs

# Using Makefile
make start           # Start container
make stop            # Stop container
make logs            # View logs
make shell           # Access shell