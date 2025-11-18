#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to prompt user for configuration
prompt_config() {
    local prompt_text=$1
    local default_value=$2
    local current_value=$3
    
    if [ -z "$current_value" ]; then
        current_value=$default_value
    fi
    
    if [ -n "$current_value" ]; then
        read -p "${prompt_text} [$current_value]: " input
        echo "${input:-$current_value}"
    else
        read -p "${prompt_text}: " input
        echo "$input"
    fi
}

# Check and create .env file if it doesn't exist
if [ ! -f .env ]; then
    if [ ! -f .env.example ]; then
        echo -e "${RED}Error: .env.example file not found${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}.env file not found, creating interactively...${NC}"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Configuration Setup${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Base configuration
    CONTAINER_NAME=$(prompt_config "Container name" "ttyd-terminal" "")
    TTYD_PORT=$(prompt_config "Port" "7681" "")
    TTYD_USER=$(prompt_config "User" "root" "")

    echo ""
    read -p "Build-time proxy? (y/N): " enable_build_proxy
    if [[ "$enable_build_proxy" =~ ^[Yy]$ ]]; then
        USE_BUILD_PROXY="true"
        BUILD_HTTP_PROXY=$(prompt_config "  HTTP proxy" "" "")
        BUILD_HTTPS_PROXY=$(prompt_config "  HTTPS proxy" "" "")
        BUILD_NO_PROXY=$(prompt_config "  NO_PROXY" "localhost,127.0.0.1" "")
    else
        USE_BUILD_PROXY="false"
        BUILD_HTTP_PROXY=""
        BUILD_HTTPS_PROXY=""
        BUILD_NO_PROXY=""
    fi

    echo ""
    NODE_VERSION=$(prompt_config "Node.js version" "24" "")
    EXTRA_APK_PACKAGES=$(prompt_config "Extra APK packages" "" "")
    EXTRA_NPM_PACKAGES=$(prompt_config "Extra NPM packages" "" "")

    echo ""
    read -p "Runtime proxy? (y/N): " enable_runtime_proxy
    if [[ "$enable_runtime_proxy" =~ ^[Yy]$ ]]; then
        USE_RUNTIME_PROXY="true"
        RUNTIME_HTTP_PROXY=$(prompt_config "  HTTP proxy" "" "")
        RUNTIME_HTTPS_PROXY=$(prompt_config "  HTTPS proxy" "" "")
        RUNTIME_NO_PROXY=$(prompt_config "  NO_PROXY" "localhost,127.0.0.1" "")
    else
        USE_RUNTIME_PROXY="false"
        RUNTIME_HTTP_PROXY=""
        RUNTIME_HTTPS_PROXY=""
        RUNTIME_NO_PROXY=""
    fi

    echo ""
    echo -e "${YELLOW}Claude Code Configuration (optional)${NC}"
    ANTHROPIC_BASE_URL=$(prompt_config "Anthropic Base URL" "" "")
    ANTHROPIC_AUTH_TOKEN=$(prompt_config "Anthropic Auth Token" "" "")
    ANTHROPIC_MODEL=$(prompt_config "Anthropic Model" "" "")
    ANTHROPIC_SMALL_FAST_MODEL=$(prompt_config "Anthropic Small Fast Model" "" "")

    # Save configuration to .env
    echo ""
    echo -e "${YELLOW}Saving configuration to .env...${NC}"
    cat > .env << EOF
# ===== BASE CONFIGURATION =====
CONTAINER_NAME=$CONTAINER_NAME
TTYD_PORT=$TTYD_PORT
TTYD_USER=$TTYD_USER

# ===== BUILD-TIME CONFIGURATION =====
# Enable proxy during container build (image creation)
USE_BUILD_PROXY=$USE_BUILD_PROXY
BUILD_HTTP_PROXY=$BUILD_HTTP_PROXY
BUILD_HTTPS_PROXY=$BUILD_HTTPS_PROXY
BUILD_NO_PROXY=$BUILD_NO_PROXY

# Node.js version (Alpine package)
NODE_VERSION=$NODE_VERSION

# Additional APK packages to install (space-separated)
# These will be added to the default runtime packages
# Example: EXTRA_APK_PACKAGES="python3 py3-pip wget"
EXTRA_APK_PACKAGES="$EXTRA_APK_PACKAGES"

# Additional NPM packages to install globally (space-separated)
# Example: EXTRA_NPM_PACKAGES="typescript nodemon pm2"
EXTRA_NPM_PACKAGES="$EXTRA_NPM_PACKAGES"

# ===== RUNTIME CONFIGURATION =====
# Enable proxy when container is running
USE_RUNTIME_PROXY=$USE_RUNTIME_PROXY
RUNTIME_HTTP_PROXY=$RUNTIME_HTTP_PROXY
RUNTIME_HTTPS_PROXY=$RUNTIME_HTTPS_PROXY
RUNTIME_NO_PROXY=$RUNTIME_NO_PROXY

# ===== CLAUDE CODE CONFIGURATION =====
# Configuration for Claude Code
ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN
ANTHROPIC_MODEL=$ANTHROPIC_MODEL
ANTHROPIC_SMALL_FAST_MODEL=$ANTHROPIC_SMALL_FAST_MODEL
EOF

    echo -e "${GREEN}✓ Configuration saved to .env${NC}"
    echo ""
fi

echo -e "${GREEN}Loading configuration from .env...${NC}"
source .env

# Validate required variables
if [ -z "$CONTAINER_NAME" ]; then
    echo -e "${RED}Error: CONTAINER_NAME is required in .env${NC}"
    exit 1
fi

if [ -z "$TTYD_PORT" ]; then
    echo -e "${RED}Error: TTYD_PORT is required in .env${NC}"
    exit 1
fi

# Function to generate Podmanfile
generate_podmanfile() {
    echo -e "${YELLOW}Generating Podmanfile...${NC}"
    
    cat > Podmanfile << 'EOF'
# =====================================
# STAGE 1: BASE
# =====================================
FROM alpine:latest AS base

# Base system packages common to both stages
RUN apk update && apk add --no-cache \
    ca-certificates \
    tzdata \
    && rm -rf /var/cache/apk/*

# =====================================
# STAGE 2: BUILD
# =====================================
FROM base AS build
EOF

    # Add build-time proxy if enabled
    if [ "$USE_BUILD_PROXY" = "true" ]; then
        cat >> Podmanfile << EOF

# Build-time proxy configuration
ARG BUILD_HTTP_PROXY=${BUILD_HTTP_PROXY}
ARG BUILD_HTTPS_PROXY=${BUILD_HTTPS_PROXY}
ARG BUILD_NO_PROXY=${BUILD_NO_PROXY}

ENV HTTP_PROXY=\${BUILD_HTTP_PROXY}
ENV HTTPS_PROXY=\${BUILD_HTTPS_PROXY}
ENV NO_PROXY=\${BUILD_NO_PROXY}
EOF
    fi

    # Add build stage content
    cat >> Podmanfile << EOF

# Install build dependencies
RUN apk add --no-cache \\
    nodejs npm \\
    && rm -rf /var/cache/apk/*
EOF

    if [ "$USE_BUILD_PROXY" = "true" ]; then
        cat >> Podmanfile << 'EOF'

# Configure npm proxy if needed
RUN if [ -n "$HTTP_PROXY" ]; then \
        npm config set proxy "$HTTP_PROXY" && \
        npm config set https-proxy "$HTTPS_PROXY"; \
    fi
EOF
    fi

    cat >> Podmanfile << 'EOF'

# Build workspace
WORKDIR /build

# Install npm packages globally
RUN npm install -g npm@latest

# =====================================
# STAGE 3: RUNTIME
# =====================================
FROM base AS runtime
EOF

    # Add runtime proxy if enabled
    if [ "$USE_RUNTIME_PROXY" = "true" ]; then
        cat >> Podmanfile << EOF

# Runtime proxy configuration
ARG RUNTIME_HTTP_PROXY=${RUNTIME_HTTP_PROXY}
ARG RUNTIME_HTTPS_PROXY=${RUNTIME_HTTPS_PROXY}
ARG RUNTIME_NO_PROXY=${RUNTIME_NO_PROXY}

ENV HTTP_PROXY=\${RUNTIME_HTTP_PROXY}
ENV HTTPS_PROXY=\${RUNTIME_HTTPS_PROXY}
ENV NO_PROXY=\${RUNTIME_NO_PROXY}
EOF
    fi

    # Add runtime stage content
    cat >> Podmanfile << 'EOF'

# Install core runtime dependencies
RUN apk add --no-cache \
    ttyd nodejs npm vim bash git curl jq tree htop tmux \
    && rm -rf /var/cache/apk/*
EOF

    # Add extra APK packages if specified
    if [ -n "$EXTRA_APK_PACKAGES" ]; then
        cat >> Podmanfile << EOF

# Install additional APK packages
RUN apk add --no-cache \\
    $EXTRA_APK_PACKAGES \\
    && rm -rf /var/cache/apk/*
EOF
    fi
    
    # Add extra NPM packages if specified
    if [ -n "$EXTRA_NPM_PACKAGES" ]; then
        cat >> Podmanfile << EOF

# Install additional NPM packages globally
RUN npm install -g $EXTRA_NPM_PACKAGES
EOF
    fi
    
    cat >> Podmanfile << 'EOF'

# Copy built artifacts from build stage
COPY --from=build /usr/lib/node_modules /usr/lib/node_modules
COPY --from=build /usr/bin/npm /usr/bin/npm
COPY --from=build /usr/bin/npx /usr/bin/npx

# Setup workspace
WORKDIR /workspace

# Copy entrypoint script
COPY scripts/entrypoint.sh /usr/local/bin/

# Copy all scripts and make them executable
COPY scripts/* /usr/local/bin/
RUN chmod +x /usr/local/bin/*

# Expose ttyd port
EXPOSE 7681

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
EOF

    echo -e "${GREEN}✓ Podmanfile generated successfully${NC}"
}

# Function to generate podman-compose.yml
generate_compose_file() {
    echo -e "${YELLOW}Generating podman-compose.yml...${NC}"
    
    cat > podman-compose.yml << EOF
version: '3.8'

services:
  ttyd-terminal:
    image: \${CONTAINER_NAME:-${CONTAINER_NAME}}
    container_name: \${CONTAINER_NAME:-${CONTAINER_NAME}}
    build:
      context: .
      dockerfile: Podmanfile
EOF

    # Add build args if proxies are enabled
    if [ "$USE_BUILD_PROXY" = "true" ] || [ "$USE_RUNTIME_PROXY" = "true" ]; then
        cat >> podman-compose.yml << EOF
      args:
EOF
        if [ "$USE_BUILD_PROXY" = "true" ]; then
            cat >> podman-compose.yml << EOF
        - BUILD_HTTP_PROXY=\${BUILD_HTTP_PROXY:-${BUILD_HTTP_PROXY}}
        - BUILD_HTTPS_PROXY=\${BUILD_HTTPS_PROXY:-${BUILD_HTTPS_PROXY}}
        - BUILD_NO_PROXY=\${BUILD_NO_PROXY:-${BUILD_NO_PROXY}}
EOF
        fi
        if [ "$USE_RUNTIME_PROXY" = "true" ]; then
            cat >> podman-compose.yml << EOF
        - RUNTIME_HTTP_PROXY=\${RUNTIME_HTTP_PROXY:-${RUNTIME_HTTP_PROXY}}
        - RUNTIME_HTTPS_PROXY=\${RUNTIME_HTTPS_PROXY:-${RUNTIME_HTTPS_PROXY}}
        - RUNTIME_NO_PROXY=\${RUNTIME_NO_PROXY:-${RUNTIME_NO_PROXY}}
EOF
        fi
    fi

    cat >> podman-compose.yml << EOF
    ports:
      - "\${TTYD_PORT:-${TTYD_PORT}}:7681"
    environment:
EOF

    # Add Claude Code environment variables
    cat >> podman-compose.yml << EOF
      # Claude Code Configuration
      - ANTHROPIC_BASE_URL=\${ANTHROPIC_BASE_URL:-${ANTHROPIC_BASE_URL}}
      - ANTHROPIC_AUTH_TOKEN=\${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_AUTH_TOKEN}}
      - ANTHROPIC_MODEL=\${ANTHROPIC_MODEL:-${ANTHROPIC_MODEL}}
      - ANTHROPIC_SMALL_FAST_MODEL=\${ANTHROPIC_SMALL_FAST_MODEL:-${ANTHROPIC_SMALL_FAST_MODEL}}
EOF

    # Add runtime proxy environment variables if enabled
    if [ "$USE_RUNTIME_PROXY" = "true" ]; then
        cat >> podman-compose.yml << EOF
      # Runtime Proxy Configuration
      - HTTP_PROXY=\${RUNTIME_HTTP_PROXY:-${RUNTIME_HTTP_PROXY}}
      - HTTPS_PROXY=\${RUNTIME_HTTPS_PROXY:-${RUNTIME_HTTPS_PROXY}}
      - NO_PROXY=\${RUNTIME_NO_PROXY:-${RUNTIME_NO_PROXY}}
EOF
    fi

    cat >> podman-compose.yml << 'EOF'
    volumes:
      # Mount workspace directory for persistent data
      - ./workspace:/workspace:z
    restart: unless-stopped
    stdin_open: true
    tty: true
    networks:
      - ttyd-network
    # Podman-specific: run as rootless
    userns_mode: "keep-id"
    security_opt:
      - label=disable

networks:
  ttyd-network:
    driver: bridge
EOF

    echo -e "${GREEN}✓ podman-compose.yml generated successfully${NC}"
}

# Build arguments
build_args=""

if [ "$USE_BUILD_PROXY" = "true" ]; then
    echo -e "${YELLOW}Build-time proxy enabled${NC}"
    if [ -n "$BUILD_HTTP_PROXY" ]; then
        build_args="$build_args --build-arg BUILD_HTTP_PROXY=${BUILD_HTTP_PROXY}"
    fi
    if [ -n "$BUILD_HTTPS_PROXY" ]; then
        build_args="$build_args --build-arg BUILD_HTTPS_PROXY=${BUILD_HTTPS_PROXY}"
    fi
    if [ -n "$BUILD_NO_PROXY" ]; then
        build_args="$build_args --build-arg BUILD_NO_PROXY=${BUILD_NO_PROXY}"
    fi
fi

if [ "$USE_RUNTIME_PROXY" = "true" ]; then
    echo -e "${YELLOW}Runtime proxy enabled${NC}"
    if [ -n "$RUNTIME_HTTP_PROXY" ]; then
        build_args="$build_args --build-arg RUNTIME_HTTP_PROXY=${RUNTIME_HTTP_PROXY}"
    fi
    if [ -n "$RUNTIME_HTTPS_PROXY" ]; then
        build_args="$build_args --build-arg RUNTIME_HTTPS_PROXY=${RUNTIME_HTTPS_PROXY}"
    fi
    if [ -n "$RUNTIME_NO_PROXY" ]; then
        build_args="$build_args --build-arg RUNTIME_NO_PROXY=${RUNTIME_NO_PROXY}"
    fi
fi

# Generate Podmanfile and podman-compose.yml
generate_podmanfile
generate_compose_file

# Handle proxy environment variables
if [ "$USE_BUILD_PROXY" != "true" ]; then
    echo -e "${YELLOW}Unsetting proxy variables for build (USE_BUILD_PROXY=false)...${NC}"
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy
    
    # Also unset proxy in Podman machine environment
    echo -e "${YELLOW}Clearing proxy settings in Podman machine...${NC}"
    podman machine ssh podman-machine-default "sudo systemctl unset-environment HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy" 2>/dev/null || true
fi

# Build image
echo -e "${GREEN}Building image: ${CONTAINER_NAME}${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"

if podman build ${build_args} -f Podmanfile -t ${CONTAINER_NAME} .; then
    echo -e "${GREEN}✓ Build complete!${NC}"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Run container with:${NC}"
    
    # Build environment variables for Claude Code if configured
    CLAUDE_ENV_VARS=""
    if [ -n "$ANTHROPIC_BASE_URL" ]; then
        CLAUDE_ENV_VARS="$CLAUDE_ENV_VARS -e ANTHROPIC_BASE_URL='$ANTHROPIC_BASE_URL'"
    fi
    if [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
        CLAUDE_ENV_VARS="$CLAUDE_ENV_VARS -e ANTHROPIC_AUTH_TOKEN='$ANTHROPIC_AUTH_TOKEN'"
    fi
    if [ -n "$ANTHROPIC_MODEL" ]; then
        CLAUDE_ENV_VARS="$CLAUDE_ENV_VARS -e ANTHROPIC_MODEL='$ANTHROPIC_MODEL'"
    fi
    if [ -n "$ANTHROPIC_SMALL_FAST_MODEL" ]; then
        CLAUDE_ENV_VARS="$CLAUDE_ENV_VARS -e ANTHROPIC_SMALL_FAST_MODEL='$ANTHROPIC_SMALL_FAST_MODEL'"
    fi
    
    echo -e "  ${YELLOW}podman run -d -p ${TTYD_PORT}:7681${CLAUDE_ENV_VARS} --name ${CONTAINER_NAME} ${CONTAINER_NAME}${NC}"
    echo ""
    echo -e "${GREEN}Access web terminal at:${NC}"
    echo -e "  ${YELLOW}http://localhost:${TTYD_PORT}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi