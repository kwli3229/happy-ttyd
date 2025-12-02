#!/bin/bash
# =====================================
# GENERATE-COMPOSE.SH - Compose File Generation
# =====================================
# This script generates podman-compose.yml from .env configuration.
# It creates a complete compose configuration with volumes, networks, and proxy settings.
#
# Usage:
#   ./scripts/generate-compose.sh
#
# Dependencies:
#   - lib/common.sh (for colors and logging)
#   - lib/env-loader.sh (for .env loading)

set -e

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "$PROJECT_ROOT/make-app/lib/common.sh"
# shellcheck source=../lib/env-loader.sh
source "$PROJECT_ROOT/make-app/lib/env-loader.sh"

# =====================================
# CONFIGURATION
# =====================================
readonly COMPOSE_FILE="$PROJECT_ROOT/podman-compose.yml"

# Note: DEFAULT_TTYD_PORT is defined in lib/common.sh

# =====================================
# HELPER FUNCTIONS
# =====================================

# Generate compose file header and service definition
generate_compose_header() {
    local ttyd_port="${TTYD_PORT:-${DEFAULT_TTYD_PORT}}"
    
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  ttyd-terminal:
    image: \${CONTAINER_NAME:-${CONTAINER_NAME}}
    build:
      context: .
      dockerfile: Podmanfile
EOF
}

# Generate build args section if proxies are enabled
generate_build_args() {
    # Check if we need build args section
    if [ "$USE_BUILD_PROXY" = "true" ] || [ "$USE_RUNTIME_PROXY" = "true" ]; then
        cat >> "$COMPOSE_FILE" << EOF
      args:
EOF
        
        # Add build-time proxy args if enabled
        if [ "$USE_BUILD_PROXY" = "true" ]; then
            cat >> "$COMPOSE_FILE" << EOF
        - BUILD_HTTP_PROXY=\${BUILD_HTTP_PROXY:-${BUILD_HTTP_PROXY}}
        - BUILD_HTTPS_PROXY=\${BUILD_HTTPS_PROXY:-${BUILD_HTTPS_PROXY}}
        - BUILD_NO_PROXY=\${BUILD_NO_PROXY:-${BUILD_NO_PROXY}}
EOF
        fi
        
        # Add runtime proxy args if enabled
        if [ "$USE_RUNTIME_PROXY" = "true" ]; then
            cat >> "$COMPOSE_FILE" << EOF
        - RUNTIME_HTTP_PROXY=\${RUNTIME_HTTP_PROXY:-${RUNTIME_HTTP_PROXY}}
        - RUNTIME_HTTPS_PROXY=\${RUNTIME_HTTPS_PROXY:-${RUNTIME_HTTPS_PROXY}}
        - RUNTIME_NO_PROXY=\${RUNTIME_NO_PROXY:-${RUNTIME_NO_PROXY}}
EOF
        fi
    fi
}

# Generate ports section
generate_ports() {
    local ttyd_port="${TTYD_PORT:-${DEFAULT_TTYD_PORT}}"
    
    cat >> "$COMPOSE_FILE" << EOF
    ports:
      # Map host port to container's ttyd port
      - "\${TTYD_PORT:-${ttyd_port}}:${DEFAULT_TTYD_PORT}"
EOF
}

# Generate environment variables section
generate_environment() {
    cat >> "$COMPOSE_FILE" << EOF
    environment:
      # Happy Coder Configuration (Anthropic API)
      - ANTHROPIC_BASE_URL=\${ANTHROPIC_BASE_URL}
      - ANTHROPIC_AUTH_TOKEN=\${ANTHROPIC_AUTH_TOKEN}
      - ANTHROPIC_MODEL=\${ANTHROPIC_MODEL}
      - ANTHROPIC_SMALL_FAST_MODEL=\${ANTHROPIC_SMALL_FAST_MODEL}
      
      # TTYD Configuration
      - TTYD_PORT=\${TTYD_PORT:-${TTYD_PORT}}
      - TTYD_FONTSIZE=\${TTYD_FONTSIZE:-16}
      
      # Runtime Proxy Configuration - Always map for entrypoint.sh compatibility
      - HTTP_PROXY=\${RUNTIME_HTTP_PROXY:-${RUNTIME_HTTP_PROXY}}
      - HTTPS_PROXY=\${RUNTIME_HTTPS_PROXY:-${RUNTIME_HTTPS_PROXY}}
      - NO_PROXY=\${RUNTIME_NO_PROXY:-${RUNTIME_NO_PROXY}}
EOF
}

# Generate volumes and other settings
generate_volumes_and_settings() {
    cat >> "$COMPOSE_FILE" << 'EOF'
    volumes:
      # Mount workspace directory for persistent data
      - ./workspace:/workspace:z
      - ./conf/happy:/root/.happy:z
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
}

# =====================================
# MAIN FUNCTIONS
# =====================================

# Generate the complete compose file
generate_compose_file() {
    log_info "Generating podman-compose.yml..."
    
    # Remove existing compose file if present
    if [ -f "$COMPOSE_FILE" ]; then
        rm -f "$COMPOSE_FILE"
    fi
    
    # Generate each section
    generate_compose_header
    generate_build_args
    generate_ports
    generate_environment
    generate_volumes_and_settings
    
    log_success "podman-compose.yml generated successfully at $COMPOSE_FILE"
}

# Display summary of generated compose file
show_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Compose File Summary${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "  ${BLUE}Service:${NC} ttyd-terminal"
    echo -e "  ${BLUE}Image:${NC} ${CONTAINER_NAME}"
    echo -e "  ${BLUE}Port Mapping:${NC} ${TTYD_PORT}:${DEFAULT_TTYD_PORT}"
    echo ""

    echo -e "  ${BLUE}Volumes:${NC}"
    echo "    - ./workspace:/workspace:z"
    echo "    - ./conf/happy:/root/.happy:z"
    echo ""
    
    if [ "$USE_BUILD_PROXY" = "true" ]; then
        echo -e "  ${BLUE}Build Proxy:${NC} Enabled"
        echo "    HTTP:  ${BUILD_HTTP_PROXY:-not set}"
        echo "    HTTPS: ${BUILD_HTTPS_PROXY:-not set}"
        echo ""
    fi
    
    if [ "$USE_RUNTIME_PROXY" = "true" ]; then
        echo -e "  ${BLUE}Runtime Proxy:${NC} Enabled"
        echo "    HTTP:  ${RUNTIME_HTTP_PROXY:-not set}"
        echo "    HTTPS: ${RUNTIME_HTTPS_PROXY:-not set}"
        echo ""
    fi
    
    if [ -n "$ANTHROPIC_BASE_URL" ]; then
        echo -e "  ${BLUE}Happy Coder:${NC} Configured"
        echo "    Base URL: ${ANTHROPIC_BASE_URL}"
        echo ""
    fi
}

# =====================================
# MAIN EXECUTION
# =====================================

main() {
    print_header "Compose File Generation"
    
    # Load and validate environment
    load_and_validate_env
    
    # Generate compose file
    generate_compose_file
    
    # Show summary
    show_summary
}

# Run main function
main "$@"