# Multi-Stage Build Guide for Podmanfile

## Overview

The Podmanfile now supports **6 stages** instead of the original 3. This demonstrates how to add custom stages for different purposes.

## Current Stages

### Stage 1: BASE
```dockerfile
FROM alpine:latest AS base
```
- **Purpose**: Common foundation for all other stages
- **Contains**: Basic system packages (ca-certificates, tzdata)
- **Used by**: All subsequent stages

### Stage 2: BUILD
```dockerfile
FROM base AS build
```
- **Purpose**: Build artifacts and compile code
- **Contains**: Build tools (nodejs, npm)
- **Use case**: Compile TypeScript, build assets, etc.

### Stage 3: DEPENDENCIES
```dockerfile
FROM base AS dependencies
```
- **Purpose**: Cache dependency installations separately
- **Benefits**: Faster rebuilds when only code changes
- **Use case**: Install npm/pip/go packages that rarely change

### Stage 4: TESTING
```dockerfile
FROM dependencies AS testing
```
- **Purpose**: Run tests before building final image
- **Contains**: Testing frameworks and tools
- **Use case**: CI/CD pipelines, pre-deployment validation

### Stage 5: DEVELOPMENT
```dockerfile
FROM dependencies AS development
```
- **Purpose**: Development environment with extra tools
- **Contains**: Debuggers, linters, hot-reload tools
- **Use case**: Local development, debugging

### Stage 6: RUNTIME
```dockerfile
FROM base AS runtime
```
- **Purpose**: Final production image
- **Contains**: Only runtime dependencies and application
- **Benefits**: Smallest possible image size

---

## How to Use Different Stages

### Build the Final Runtime Image (Default)
```bash
podman build -t happy-ttyd:latest -f Podmanfile .
```

### Build a Specific Stage
```bash
# Build only the dependencies stage
podman build --target dependencies -t happy-ttyd:deps -f Podmanfile .

# Build the development stage
podman build --target development -t happy-ttyd:dev -f Podmanfile .

# Build the testing stage (useful in CI)
podman build --target testing -t happy-ttyd:test -f Podmanfile .
```

### Run Different Stages
```bash
# Run development environment
podman run -it --rm happy-ttyd:dev bash

# Run tests
podman run --rm happy-ttyd:test npm test

# Run production
podman run -d -p 7681:7681 happy-ttyd:latest
```

---

## Adding Your Own Custom Stages

### Pattern 1: Linear Dependency Chain
```dockerfile
# Each stage builds on the previous one
FROM base AS stage1
# ... install layer 1 packages

FROM stage1 AS stage2
# ... install layer 2 packages

FROM stage2 AS final
# ... install layer 3 packages
```

### Pattern 2: Parallel Stages
```dockerfile
# Multiple stages branch from the same base
FROM base AS build-frontend
# ... build frontend

FROM base AS build-backend
# ... build backend

FROM base AS final
COPY --from=build-frontend /app/dist /app/frontend
COPY --from=build-backend /app/bin /app/backend
```

### Pattern 3: Stage with External Image
```dockerfile
# Use a completely different base for specific stages
FROM node:20-alpine AS node-builder
# ... use Node.js specific features

FROM base AS final
COPY --from=node-builder /build/output /app
```

---

## Example Custom Stages

### Add a Documentation Stage
```dockerfile
# =====================================
# STAGE: DOCUMENTATION
# =====================================
FROM base AS documentation

RUN apk add --no-cache \
    python3 py3-pip \
    && pip install mkdocs mkdocs-material

WORKDIR /docs
COPY docs/ .
RUN mkdocs build
```

### Add a Security Scanning Stage
```dockerfile
# =====================================
# STAGE: SECURITY
# =====================================
FROM runtime AS security

RUN apk add --no-cache \
    trivy \
    && trivy filesystem --exit-code 1 /
```

### Add a Monitoring/Debug Stage
```dockerfile
# =====================================
# STAGE: DEBUG
# =====================================
FROM runtime AS debug

# Add debugging and profiling tools
RUN apk add --no-cache \
    strace gdb valgrind \
    perf-tools \
    && rm -rf /var/cache/apk/*
```

### Add a Data Processing Stage
```dockerfile
# =====================================
# STAGE: DATA-PROCESSOR
# =====================================
FROM base AS data-processor

RUN apk add --no-cache \
    python3 py3-pip \
    && pip install pandas numpy scipy

WORKDIR /data
```

---

## Best Practices

1. **Order Matters**: Place stages that change frequently later in the file
2. **Cache Optimization**: Separate dependency installation from code copying
3. **Minimize Final Image**: Only copy what's needed from build stages
4. **Stage Naming**: Use descriptive names (e.g., `builder`, `tester`, `runtime`)
5. **FROM Selection**: Choose the appropriate base for each stage's purpose

## Example Multi-Stage Build Command
```bash
# Build and tag multiple stages at once
podman build -f Podmanfile \
  --target development -t happy-ttyd:dev \
  --target testing -t happy-ttyd:test \
  --target runtime -t happy-ttyd:latest \
  .
```

## Tips

- **You can have unlimited stages** - add as many as needed
- Each stage is independent and can be built separately with `--target`
- Use [`COPY --from=stage-name`](https://docs.docker.com/engine/reference/builder/#copy) to copy files between stages
- Stages you don't target won't be built, saving time
- Comment your stages clearly to explain their purpose

---

## Further Reading

- [Docker Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Podman Build Documentation](https://docs.podman.io/en/latest/markdown/podman-build.1.html)