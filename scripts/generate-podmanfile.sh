#!/bin/bash
# =====================================
# GENERATE-PODMANFILE.SH - Podmanfile Generation
# =====================================
# This script generates a multi-stage Podmanfile from .env configuration.
# It creates a 3-stage build: base, build, and runtime with conditional proxy support.
#
# Usage:
#   ./scripts/generate-podmanfile.sh
#
# Dependencies:
#   - lib/common.sh (for colors and logging)
#   - lib/env-loader.sh (for .env loading)
#   - lib/proxy-handler.sh (for proxy configuration)

set -e

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=../lib/env-loader.sh
source "$PROJECT_ROOT/lib/env-loader.sh"
# shellcheck source=../lib/proxy-handler.sh
source "$PROJECT_ROOT/lib/proxy-handler.sh"

# =====================================
# CONFIGURATION
# =====================================
readonly PODMANFILE="$PROJECT_ROOT/Podmanfile"

# Note: SCRIPTS_DIR, ENTRYPOINT_SCRIPT, and package arrays are defined in lib/common.sh

# =====================================
# HELPER FUNCTIONS
# =====================================

# Generate the base stage
generate_base_stage() {
    cat >> "$PODMANFILE" << EOF
# =====================================
# STAGE 1: BASE
# =====================================
FROM alpine:${DEFAULT_ALPINE_VERSION} AS base

# Base system packages common to both stages
RUN apk update && apk add --no-cache \\
    ca-certificates \\
    tzdata \\
    && rm -rf /var/cache/apk/*

EOF
}

# Generate the build stage
generate_build_stage() {
    cat >> "$PODMANFILE" << 'EOF'
# =====================================
# STAGE 2: BUILD
# =====================================
FROM base AS build
EOF

    # Add build-time proxy if enabled
    if [ "$USE_BUILD_PROXY" = "true" ]; then
        cat >> "$PODMANFILE" << 'EOF'

# Build-time proxy configuration
ARG BUILD_HTTP_PROXY=${BUILD_HTTP_PROXY}
ARG BUILD_HTTPS_PROXY=${BUILD_HTTPS_PROXY}
ARG BUILD_NO_PROXY=${BUILD_NO_PROXY}

ENV HTTP_PROXY=${BUILD_HTTP_PROXY}
ENV HTTPS_PROXY=${BUILD_HTTPS_PROXY}
ENV NO_PROXY=${BUILD_NO_PROXY}
EOF
    fi

    # Add build stage content
    cat >> "$PODMANFILE" << EOF

# Install build dependencies
RUN apk add --no-cache \\
    ${BUILD_PACKAGES[@]} \\
    && rm -rf /var/cache/apk/*
EOF

    # Configure npm proxy if needed
    if [ "$USE_BUILD_PROXY" = "true" ]; then
        cat >> "$PODMANFILE" << 'EOF'

# Configure npm proxy if needed
RUN if [ -n "$HTTP_PROXY" ]; then \
        npm config set proxy "$HTTP_PROXY" && \
        npm config set https-proxy "$HTTPS_PROXY"; \
    fi
EOF
    fi

    cat >> "$PODMANFILE" << 'EOF'

# Build workspace
WORKDIR /build

# Install npm packages globally
RUN npm install -g npm@latest

EOF
}

# Generate the runtime stage
generate_runtime_stage() {
    cat >> "$PODMANFILE" << 'EOF'
# =====================================
# STAGE 3: RUNTIME
# =====================================
FROM base AS runtime
EOF

    # Add runtime proxy if enabled
    if [ "$USE_RUNTIME_PROXY" = "true" ]; then
        cat >> "$PODMANFILE" << EOF

# Runtime proxy configuration
ARG RUNTIME_HTTP_PROXY=${RUNTIME_HTTP_PROXY}
ARG RUNTIME_HTTPS_PROXY=${RUNTIME_HTTPS_PROXY}
ARG RUNTIME_NO_PROXY=${RUNTIME_NO_PROXY}

ENV HTTP_PROXY=\${RUNTIME_HTTP_PROXY}
ENV HTTPS_PROXY=\${RUNTIME_HTTPS_PROXY}
ENV NO_PROXY=\${RUNTIME_NO_PROXY}
EOF
    fi

    # Build the package list dynamically
    local runtime_packages="${RUNTIME_CORE_PACKAGES[*]}"
    
    cat >> "$PODMANFILE" << EOF

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
        cat >> "$PODMANFILE" << EOF

# Install additional APK packages
RUN apk add --no-cache \\
    $EXTRA_APK_PACKAGES \\
    && rm -rf /var/cache/apk/*
EOF
    fi
    
    # Add extra NPM packages if specified
    if [ -n "$EXTRA_NPM_PACKAGES" ]; then
        cat >> "$PODMANFILE" << EOF

# Install additional NPM packages globally
RUN npm install -g $EXTRA_NPM_PACKAGES
EOF
    fi
    
    # Copy built artifacts and configure container
    cat >> "$PODMANFILE" << EOF

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
}

# =====================================
# MAIN FUNCTIONS
# =====================================

# Generate the complete Podmanfile
generate_podmanfile() {
    log_info "Generating Podmanfile..."
    
    # Remove existing Podmanfile if present
    if [ -f "$PODMANFILE" ]; then
        rm -f "$PODMANFILE"
    fi
    
    # Generate each stage
    generate_base_stage
    generate_build_stage
    generate_runtime_stage
    
    log_success "Podmanfile generated successfully at $PODMANFILE"
}

# Display summary of generated Podmanfile
show_summary() {
    echo ""
    print_header "Podmanfile Summary"
    
    echo -e "  ${BLUE}Stages:${NC}"
    echo "    1. Base (Alpine ${DEFAULT_ALPINE_VERSION})"
    echo "    2. Build (Node.js build dependencies)"
    echo "    3. Runtime (Final image)"
    echo ""
    
    echo -e "  ${BLUE}Build Proxy:${NC} $([ "$USE_BUILD_PROXY" = "true" ] && echo "Enabled" || echo "Disabled")"
    if [ "$USE_BUILD_PROXY" = "true" ]; then
        echo "    HTTP:  ${BUILD_HTTP_PROXY:-not set}"
        echo "    HTTPS: ${BUILD_HTTPS_PROXY:-not set}"
    fi
    echo ""
    
    echo -e "  ${BLUE}Runtime Proxy:${NC} $([ "$USE_RUNTIME_PROXY" = "true" ] && echo "Enabled" || echo "Disabled")"
    if [ "$USE_RUNTIME_PROXY" = "true" ]; then
        echo "    HTTP:  ${RUNTIME_HTTP_PROXY:-not set}"
        echo "    HTTPS: ${RUNTIME_HTTPS_PROXY:-not set}"
    fi
    echo ""
    
    if [ -n "$EXTRA_APK_PACKAGES" ]; then
        echo -e "  ${BLUE}Extra APK Packages:${NC} $EXTRA_APK_PACKAGES"
        echo ""
    fi
    
    if [ -n "$EXTRA_NPM_PACKAGES" ]; then
        echo -e "  ${BLUE}Extra NPM Packages:${NC} $EXTRA_NPM_PACKAGES"
        echo ""
    fi
}

# =====================================
# MAIN EXECUTION
# =====================================

main() {
    print_header "Podmanfile Generation"
    
    # Load and validate environment
    load_and_validate_env
    
    # Generate Podmanfile
    generate_podmanfile
    
    # Show summary
    show_summary
}

# Run main function
main "$@"