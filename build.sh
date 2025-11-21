#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =====================================
# COMMAND LINE PARSING
# =====================================
COMMAND="${1:-build}"

# Display help if requested
if [[ "$COMMAND" == "-h" ]] || [[ "$COMMAND" == "--help" ]]; then
    echo -e "${GREEN}Usage:${NC} $0 [COMMAND]"
    echo ""
    echo -e "${GREEN}Description:${NC}"
    echo "  Build script for ttyd web terminal container. Generates Podmanfile and"
    echo "  podman-compose.yml from .env configuration, and builds the container."
    echo "  Supports GitHub Container Registry (ghcr.io) for image distribution."
    echo ""
    echo -e "${GREEN}Commands:${NC}"
    echo "  build                  Generate files and build container (default)"
    echo "  build-and-push         Generate, build, and push to ghcr.io"
    echo "  push-to-ghcr           Push existing image to ghcr.io"
    echo "  generate-podmanfile    Generate Podmanfile only"
    echo "  generate-compose       Generate podman-compose.yml only"
    echo "  generate-all           Generate both Podmanfile and podman-compose.yml"
    echo ""
    echo -e "${GREEN}Examples:${NC}"
    echo -e "  ${YELLOW}$0${NC}                         ${GREEN}# Generate files and build container${NC}"
    echo -e "  ${YELLOW}$0 build${NC}                   ${GREEN}# Same as above${NC}"
    echo -e "  ${YELLOW}$0 build-and-push${NC}           ${GREEN}# Build and push to ghcr.io${NC}"
    echo -e "  ${YELLOW}$0 push-to-ghcr${NC}             ${GREEN}# Push existing image to ghcr.io${NC}"
    echo -e "  ${YELLOW}$0 generate-all${NC}            ${GREEN}# Only generate files, skip build${NC}"
    echo -e "  ${YELLOW}$0 generate-podmanfile${NC}     ${GREEN}# Only generate Podmanfile${NC}"
    echo ""
    echo -e "${GREEN}Environment Variables:${NC}"
    echo -e "  ${YELLOW}ALPINE_VERSION${NC}       Override Alpine version (default: latest)"
    echo -e "  ${YELLOW}NODE_VERSION${NC}         Override Node.js version (default: 24)"
    echo -e "  ${YELLOW}TTYD_PORT${NC}           Override ttyd port (default: 7681)"
    echo -e "  ${YELLOW}USE_GHCR${NC}            Enable GitHub Container Registry (true/false)"
    echo -e "  ${YELLOW}GHCR_USERNAME${NC}       GitHub username for authentication"
    echo -e "  ${YELLOW}GHCR_TOKEN${NC}          GitHub personal access token"
    echo -e "  ${YELLOW}GHCR_REPOSITORY${NC}     Repository name in ghcr.io"
    echo ""
    exit 0
fi

# =====================================
# CONFIGURATION VARIABLES
# =====================================
# These variables define default values for the build process.
# They can be overridden by setting environment variables before running this script.
#
# Examples:
#   ALPINE_VERSION=3.18 ./build.sh        # Use specific Alpine version
#   NODE_VERSION=20 ./build.sh            # Use Node.js 20 instead of 24
#   TTYD_PORT=8080 ./build.sh             # Use port 8080 instead of 7681
#
# Note: These are build-time configurations. Runtime configurations should be
# set in the .env file (TTYD_PORT, CONTAINER_NAME, etc.)

# Container base image configuration
readonly DEFAULT_ALPINE_VERSION="${ALPINE_VERSION:-latest}"
readonly DEFAULT_NODE_VERSION="${NODE_VERSION:-24}"
readonly DEFAULT_TTYD_PORT="${TTYD_PORT:-7681}"

# Path configuration
readonly SCRIPTS_DIR="conf/scripts"
readonly ENTRYPOINT_SCRIPT="entrypoint.sh"

# Build stage packages
# These packages are installed only during the build stage and are not included in the final image
readonly BUILD_PACKAGES=(
    "nodejs"
    "npm"
)

# Runtime stage core packages
# These packages are installed in the final runtime image
# Additional packages can be specified in .env via EXTRA_APK_PACKAGES
readonly RUNTIME_CORE_PACKAGES=(
    "ttyd"
    "nodejs"
    "npm"
    "vim"
    "bash"
    "git"
    "curl"
    "jq"
    "tree"
    "htop"
    "tmux"
    "musl-locales"
    "musl-locales-lang"
    "font-noto-emoji"
    "font-noto-cjk"
)

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

# Function to authenticate with GitHub Container Registry
authenticate_ghcr() {
    if [ "$USE_GHCR" != "true" ]; then
        return 0
    fi
    
    if [ -z "$GHCR_USERNAME" ] || [ -z "$GHCR_TOKEN" ]; then
        echo -e "${RED}Error: GHCR_USERNAME and GHCR_TOKEN are required for ghcr.io authentication${NC}"
        echo -e "${YELLOW}Set USE_GHCR=true and provide GHCR_USERNAME and GHCR_TOKEN in .env${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Authenticating with GitHub Container Registry...${NC}"
    
    # Login to ghcr.io using podman
    if podman login ghcr.io -u "$GHCR_USERNAME" -p "$GHCR_TOKEN"; then
        echo -e "${GREEN}✓ Authentication successful${NC}"
    else
        echo -e "${RED}✗ Authentication failed${NC}"
        return 1
    fi
}

# Function to push image to GitHub Container Registry
push_to_ghcr() {
    if [ "$USE_GHCR" != "true" ]; then
        return 0
    fi
    
    # Validate required variables
    if [ -z "$GHCR_USERNAME" ] || [ -z "$GHCR_TOKEN" ] || [ -z "$GHCR_REPOSITORY" ]; then
        echo -e "${RED}Error: Cannot push to ghcr.io - missing required configuration${NC}"
        echo -e "${YELLOW}Required variables: GHCR_USERNAME, GHCR_TOKEN, GHCR_REPOSITORY${NC}"
        return 1
    fi
    
    # Generate image tag
    local image_tag="ghcr.io/$GHCR_USERNAME/$GHCR_REPOSITORY:$CONTAINER_NAME"
    
    echo -e "${YELLOW}Pushing image to GitHub Container Registry...${NC}"
    echo -e "${YELLOW}Image: $image_tag${NC}"
    
    # Tag the local image
    if ! podman tag "$CONTAINER_NAME" "$image_tag"; then
        echo -e "${RED}✗ Failed to tag image${NC}"
        return 1
    fi
    
    # Push to ghcr.io
    if podman push "$image_tag"; then
        echo -e "${GREEN}✓ Image pushed successfully to $image_tag${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to push image to ghcr.io${NC}"
        return 1
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
    TTYD_FONTSIZE=$(prompt_config "TTYD font size" "16" "")

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
    read -p "GitHub Container Registry? (y/N): " enable_ghcr
    if [[ "$enable_ghcr" =~ ^[Yy]$ ]]; then
        USE_GHCR="true"
        GHCR_USERNAME=$(prompt_config "  GitHub username" "" "")
        GHCR_TOKEN=$(prompt_config "  GitHub personal access token" "" "")
        GHCR_REPOSITORY=$(prompt_config "  Repository name" "claude-terminal" "")
    else
        USE_GHCR="false"
        GHCR_USERNAME=""
        GHCR_TOKEN=""
        GHCR_REPOSITORY="claude-terminal"
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
    
    # ===== CONTAINER REGISTRY CONFIGURATION =====
    # GitHub Container Registry configuration
    USE_GHCR=$USE_GHCR
    GHCR_USERNAME=$GHCR_USERNAME
    GHCR_TOKEN=$GHCR_TOKEN
    GHCR_REPOSITORY=$GHCR_REPOSITORY
    
    # ===== RUNTIME CONFIGURATION =====
    # Enable proxy when container is running
    USE_RUNTIME_PROXY=$USE_RUNTIME_PROXY
    RUNTIME_HTTP_PROXY=$RUNTIME_HTTP_PROXY
    RUNTIME_HTTPS_PROXY=$RUNTIME_HTTPS_PROXY
    RUNTIME_NO_PROXY=$RUNTIME_NO_PROXY
    
    # TTYD Terminal Configuration
    TTYD_FONTSIZE=$TTYD_FONTSIZE
    
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

# DEBUG: Log all environment variables related to proxy and build
echo -e "${YELLOW}=== DEBUG: Environment Variables ===${NC}"
echo -e "USE_BUILD_PROXY: ${USE_BUILD_PROXY:-'not set'}"
echo -e "BUILD_HTTP_PROXY: ${BUILD_HTTP_PROXY:-'not set'}"
echo -e "BUILD_HTTPS_PROXY: ${BUILD_HTTPS_PROXY:-'not set'}"
echo -e "BUILD_NO_PROXY: ${BUILD_NO_PROXY:-'not set'}"
echo -e "USE_RUNTIME_PROXY: ${USE_RUNTIME_PROXY:-'not set'}"
echo -e "RUNTIME_HTTP_PROXY: ${RUNTIME_HTTP_PROXY:-'not set'}"
echo -e "RUNTIME_HTTPS_PROXY: ${RUNTIME_HTTPS_PROXY:-'not set'}"
echo -e "RUNTIME_NO_PROXY: ${RUNTIME_NO_PROXY:-'not set'}"
echo -e "CONTAINER_NAME: ${CONTAINER_NAME:-'not set'}"
echo -e "TTYD_PORT: ${TTYD_PORT:-'not set'}"
echo ""

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
    
    cat > Podmanfile << EOF
# =====================================
# STAGE 1: BASE
# =====================================
FROM alpine:${DEFAULT_ALPINE_VERSION} AS base

# Base system packages common to both stages
RUN apk update && apk add --no-cache \\
    ca-certificates \\
    tzdata \\
    && rm -rf /var/cache/apk/*

# =====================================
# STAGE 2: BUILD
# =====================================
FROM base AS build
EOF

    # Add build-time proxy if enabled
    if [ "$USE_BUILD_PROXY" = "true" ]; then
        cat >> Podmanfile << 'EOF'

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
    ${BUILD_PACKAGES[@]} \\
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
    # Build the package list dynamically
    local runtime_packages="${RUNTIME_CORE_PACKAGES[*]}"
    
    cat >> Podmanfile << EOF

# Set UTF-8 locale environment variables for emoji support
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install core runtime dependencies
RUN apk add --no-cache \\
    ${runtime_packages} \\
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
        cat >> Podmanfile << 'EOF'

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
COPY ${SCRIPTS_DIR}/${ENTRYPOINT_SCRIPT} /usr/local/bin/

# Copy all scripts and make them executable
COPY ${SCRIPTS_DIR}/* /usr/local/bin/
RUN chmod +x /usr/local/bin/*

# Expose ttyd port
EXPOSE ${DEFAULT_TTYD_PORT}

# Entrypoint
ENTRYPOINT ["/usr/local/bin/${ENTRYPOINT_SCRIPT}"]
CMD ["bash"]
EOF

    echo -e "${GREEN}✓ Podmanfile generated successfully${NC}"
# Function to generate podman-compose.yml
generate_compose_file() {
    echo -e "${YELLOW}Generating podman-compose.yml...${NC}"
    
    # Use the configured port from environment or default
    local ttyd_port="${TTYD_PORT:-${DEFAULT_TTYD_PORT}}"
    
    cat > podman-compose.yml << EOF
version: '3.8'

services:
  ttyd-terminal:
    image: \${CONTAINER_NAME:-${CONTAINER_NAME}}
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
      # Map host port to container's ttyd port
      - "\${TTYD_PORT:-${ttyd_port}}:${DEFAULT_TTYD_PORT}"
    environment:
EOF

    # Add Claude Code environment variables
    cat >> podman-compose.yml << EOF
      # Claude Code Configuration
      - ANTHROPIC_BASE_URL=\${ANTHROPIC_BASE_URL}
      - ANTHROPIC_AUTH_TOKEN=\${ANTHROPIC_AUTH_TOKEN}
      - ANTHROPIC_MODEL=\${ANTHROPIC_MODEL}
      - ANTHROPIC_SMALL_FAST_MODEL=\${ANTHROPIC_SMALL_FAST_MODEL}
      
      # TTYD Configuration
      - TTYD_PORT=\${TTYD_PORT:-${TTYD_PORT}}
      - TTYD_FONTSIZE=\${TTYD_FONTSIZE:-16}
EOF

    # Always map runtime proxy variables for entrypoint compatibility
    cat >> podman-compose.yml << EOF
      # Runtime Proxy Configuration - Always map for entrypoint.sh compatibility
      - HTTP_PROXY=\${RUNTIME_HTTP_PROXY:-${RUNTIME_HTTP_PROXY}}
      - HTTPS_PROXY=\${RUNTIME_HTTPS_PROXY:-${RUNTIME_HTTPS_PROXY}}
      - NO_PROXY=\${RUNTIME_NO_PROXY:-${RUNTIME_NO_PROXY}}
EOF

    cat >> podman-compose.yml << 'EOF'
    volumes:
      # Mount workspace directory for persistent data
      - ./workspace:/workspace:z
      - ./conf/happy:/root/.happy:z
      - ./conf/claude:/root/.claude:z
    restart: unless-stopped
    stdin_open: true
    tty: true
    networks:
      - ttyd-network
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

# DEBUG: Log proxy configuration decisions
echo -e "${YELLOW}=== DEBUG: Proxy Configuration ===${NC}"
echo -e "USE_BUILD_PROXY: ${USE_BUILD_PROXY:-'false'}"
echo -e "USE_RUNTIME_PROXY: ${USE_RUNTIME_PROXY:-'false'}"

if [ "$USE_BUILD_PROXY" = "true" ]; then
    echo -e "${YELLOW}Build-time proxy enabled${NC}"
    if [ -n "$BUILD_HTTP_PROXY" ]; then
        echo -e "${YELLOW}Adding BUILD_HTTP_PROXY argument: ${BUILD_HTTP_PROXY}${NC}"
        build_args="$build_args --build-arg BUILD_HTTP_PROXY=${BUILD_HTTP_PROXY}"
    else
        echo -e "${RED}Warning: USE_BUILD_PROXY=true but BUILD_HTTP_PROXY is empty${NC}"
    fi
    if [ -n "$BUILD_HTTPS_PROXY" ]; then
        echo -e "${YELLOW}Adding BUILD_HTTPS_PROXY argument: ${BUILD_HTTPS_PROXY}${NC}"
        build_args="$build_args --build-arg BUILD_HTTPS_PROXY=${BUILD_HTTPS_PROXY}"
    else
        echo -e "${RED}Warning: USE_BUILD_PROXY=true but BUILD_HTTPS_PROXY is empty${NC}"
    fi
    if [ -n "$BUILD_NO_PROXY" ]; then
        echo -e "${YELLOW}Adding BUILD_NO_PROXY argument: ${BUILD_NO_PROXY}${NC}"
        build_args="$build_args --build-arg BUILD_NO_PROXY=${BUILD_NO_PROXY}"
    else
        echo -e "${RED}Warning: USE_BUILD_PROXY=true but BUILD_NO_PROXY is empty${NC}"
    fi
else
    echo -e "${YELLOW}Build-time proxy disabled${NC}"
fi

if [ "$USE_RUNTIME_PROXY" = "true" ]; then
    echo -e "${YELLOW}Runtime proxy enabled${NC}"
    if [ -n "$RUNTIME_HTTP_PROXY" ]; then
        echo -e "${YELLOW}Adding RUNTIME_HTTP_PROXY argument: ${RUNTIME_HTTP_PROXY}${NC}"
        build_args="$build_args --build-arg RUNTIME_HTTP_PROXY=${RUNTIME_HTTP_PROXY}"
    else
        echo -e "${RED}Warning: USE_RUNTIME_PROXY=true but RUNTIME_HTTP_PROXY is empty${NC}"
    fi
    if [ -n "$RUNTIME_HTTPS_PROXY" ]; then
        echo -e "${YELLOW}Adding RUNTIME_HTTPS_PROXY argument: ${RUNTIME_HTTPS_PROXY}${NC}"
        build_args="$build_args --build-arg RUNTIME_HTTPS_PROXY=${RUNTIME_HTTPS_PROXY}"
    else
        echo -e "${RED}Warning: USE_RUNTIME_PROXY=true but RUNTIME_HTTPS_PROXY is empty${NC}"
    fi
    if [ -n "$RUNTIME_NO_PROXY" ]; then
        echo -e "${YELLOW}Adding RUNTIME_NO_PROXY argument: ${RUNTIME_NO_PROXY}${NC}"
        build_args="$build_args --build-arg RUNTIME_NO_PROXY=${RUNTIME_NO_PROXY}"
    else
        echo -e "${RED}Warning: USE_RUNTIME_PROXY=true but RUNTIME_NO_PROXY is empty${NC}"
    fi
else
    echo -e "${YELLOW}Runtime proxy disabled${NC}"
fi

# DEBUG: Log final build_args
echo -e "${YELLOW}=== DEBUG: Final Build Arguments ===${NC}"
echo -e "build_args: '${build_args}'"
echo ""

# Execute command
case "$COMMAND" in
    generate-podmanfile)
        generate_podmanfile
        exit 0
        ;;
    generate-compose)
        generate_compose_file
        exit 0
        ;;
    generate-all)
        generate_podmanfile
        generate_compose_file
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✓ Generation complete!${NC}"
        echo ""
        echo -e "${GREEN}Generated files:${NC}"
        echo -e "  ${YELLOW}• Podmanfile${NC}"
        echo -e "  ${YELLOW}• podman-compose.yml${NC}"
        echo ""
        echo -e "${GREEN}To build the container, run:${NC}"
        echo -e "  ${YELLOW}$0 build${NC}               ${GREEN}# Generate and build${NC}"
        echo -e "  ${YELLOW}$0 build-and-push${NC}       ${GREEN}# Generate, build, and push to ghcr.io${NC}"
        echo -e "  ${YELLOW}$0 push-to-ghcr${NC}          ${GREEN}# Push existing image to ghcr.io${NC}"
        echo -e "  ${YELLOW}make build${NC}              ${GREEN}# Or use Makefile${NC}"
        echo -e "  ${YELLOW}podman build -f Podmanfile -t ${CONTAINER_NAME} .${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 0
        ;;
    build)
        # Generate Podmanfile and compose before building
        generate_podmanfile
        generate_compose_file
        ;;
    build-and-push)
        # Generate Podmanfile and compose before building
        generate_podmanfile
        generate_compose_file
        
        # Build image
        echo -e "${GREEN}Building image: ${CONTAINER_NAME}${NC}"
        echo -e "${YELLOW}This may take a few minutes...${NC}"
        
        if podman build ${build_args} -f Podmanfile -t ${CONTAINER_NAME} .; then
            echo -e "${GREEN}✓ Build complete!${NC}"
            
            # Authenticate and push to ghcr.io
            authenticate_ghcr
            if [ $? -eq 0 ]; then
                push_to_ghcr
            fi
        else
            echo -e "${RED}✗ Build failed${NC}"
            exit 1
        fi
        ;;
    push-to-ghcr)
        # Authenticate and push existing image to ghcr.io
        authenticate_ghcr
        if [ $? -eq 0 ]; then
            push_to_ghcr
        fi
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$COMMAND'${NC}"
        echo -e "Run '${YELLOW}$0 --help${NC}' for usage information"
        exit 1
        ;;
esac

# Handle proxy environment variables
if [ "$USE_BUILD_PROXY" != "true" ]; then
    echo -e "${YELLOW}Unsetting proxy variables for build (USE_BUILD_PROXY=false)...${NC}"
    echo -e "${YELLOW}Current HTTP_PROXY: ${HTTP_PROXY:-'not set'}${NC}"
    echo -e "${YELLOW}Current HTTPS_PROXY: ${HTTPS_PROXY:-'not set'}${NC}"
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy
    echo -e "${YELLOW}After unsetting - HTTP_PROXY: ${HTTP_PROXY:-'unavailable'}${NC}"
    
    # Also unset proxy in Podman machine environment
    echo -e "${YELLOW}Clearing proxy settings in Podman machine...${NC}"
    if podman machine exists; then
        echo -e "${YELLOW}Podman machine exists, attempting to clear proxy settings...${NC}"
        podman machine ssh podman-machine-default "sudo systemctl unset-environment HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy" 2>/dev/null || echo -e "${RED}Warning: Failed to clear proxy in Podman machine${NC}"
    else
        echo -e "${YELLOW}Podman machine does not exist, skipping proxy cleanup${NC}"
    fi
else
    echo -e "${YELLOW}Build proxy is enabled, keeping proxy variables set${NC}"
fi

# Build image
echo -e "${GREEN}Building image: ${CONTAINER_NAME}${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"
echo -e "${YELLOW}Build command: podman build ${build_args} -f Podmanfile -t ${CONTAINER_NAME} .${NC}"

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
    
    echo -e "  ${YELLOW}podman run -d -p ${TTYD_PORT}:${DEFAULT_TTYD_PORT}${CLAUDE_ENV_VARS} --name ${CONTAINER_NAME} ${CONTAINER_NAME}${NC}"
    echo ""
    echo -e "${GREEN}Access web terminal at:${NC}"
    echo -e "  ${YELLOW}http://localhost:${TTYD_PORT}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    echo -e "${RED}=== DEBUG: Build failure details ===${NC}"
    echo -e "${RED}build_args: '${build_args}'${NC}"
    echo -e "${RED}CONTAINER_NAME: '${CONTAINER_NAME}'${NC}"
    echo -e "${RED}Podmanfile exists: $(test -f Podmanfile && echo 'yes' || echo 'no')${NC}"
    if [ -f Podmanfile ]; then
        echo -e "${RED}Podmanfile first 10 lines:${NC}"
        head -10 Podmanfile
    fi
    exit 1
fi

# End of script
echo -e "${GREEN}Build script completed.${NC}"