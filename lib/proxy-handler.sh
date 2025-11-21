#!/bin/bash
# lib/proxy-handler.sh - Proxy configuration handling for build and runtime
# This library manages proxy settings for both build-time and runtime environments

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"

# =====================================
# BUILD PROXY FUNCTIONS
# =====================================

prepare_build_proxy_args() {
    local build_args=""
    
    if ! is_true "$USE_BUILD_PROXY"; then
        log_debug "Build proxy disabled"
        return 0
    fi
    
    log_debug "Build proxy enabled, preparing arguments..."
    
    # Add BUILD_HTTP_PROXY if set
    if is_set BUILD_HTTP_PROXY; then
        log_debug "Adding BUILD_HTTP_PROXY: $BUILD_HTTP_PROXY"
        build_args="$build_args --build-arg BUILD_HTTP_PROXY=${BUILD_HTTP_PROXY}"
    fi
    
    # Add BUILD_HTTPS_PROXY if set
    if is_set BUILD_HTTPS_PROXY; then
        log_debug "Adding BUILD_HTTPS_PROXY: $BUILD_HTTPS_PROXY"
        build_args="$build_args --build-arg BUILD_HTTPS_PROXY=${BUILD_HTTPS_PROXY}"
    fi
    
    # Add BUILD_NO_PROXY if set
    if is_set BUILD_NO_PROXY; then
        log_debug "Adding BUILD_NO_PROXY: $BUILD_NO_PROXY"
        build_args="$build_args --build-arg BUILD_NO_PROXY=${BUILD_NO_PROXY}"
    fi
    
    echo "$build_args"
}

prepare_runtime_proxy_args() {
    local runtime_args=""
    
    if ! is_true "$USE_RUNTIME_PROXY"; then
        log_debug "Runtime proxy disabled"
        return 0
    fi
    
    log_debug "Runtime proxy enabled, preparing arguments..."
    
    # Add RUNTIME_HTTP_PROXY if set
    if is_set RUNTIME_HTTP_PROXY; then
        log_debug "Adding RUNTIME_HTTP_PROXY: $RUNTIME_HTTP_PROXY"
        runtime_args="$runtime_args --build-arg RUNTIME_HTTP_PROXY=${RUNTIME_HTTP_PROXY}"
    fi
    
    # Add RUNTIME_HTTPS_PROXY if set
    if is_set RUNTIME_HTTPS_PROXY; then
        log_debug "Adding RUNTIME_HTTPS_PROXY: $RUNTIME_HTTPS_PROXY"
        runtime_args="$runtime_args --build-arg RUNTIME_HTTPS_PROXY=${RUNTIME_HTTPS_PROXY}"
    fi
    
    # Add RUNTIME_NO_PROXY if set
    if is_set RUNTIME_NO_PROXY; then
        log_debug "Adding RUNTIME_NO_PROXY: $RUNTIME_NO_PROXY"
        runtime_args="$runtime_args --build-arg RUNTIME_NO_PROXY=${RUNTIME_NO_PROXY}"
    fi
    
    echo "$runtime_args"
}

# Combine both build and runtime proxy args
prepare_all_proxy_args() {
    local build_args
    local runtime_args
    
    build_args=$(prepare_build_proxy_args)
    runtime_args=$(prepare_runtime_proxy_args)
    
    echo "$build_args $runtime_args"
}

# =====================================
# HOST PROXY CLEANUP
# =====================================

unset_host_proxies() {
    if is_true "$USE_BUILD_PROXY"; then
        log_debug "Build proxy enabled, keeping host environment variables"
        return 0
    fi
    
    log_info "Unsetting host proxy variables (USE_BUILD_PROXY=false)..."
    
    # Log current state
    log_debug "Before unset - HTTP_PROXY: ${HTTP_PROXY:-'not set'}"
    log_debug "Before unset - HTTPS_PROXY: ${HTTPS_PROXY:-'not set'}"
    
    # Unset all proxy-related environment variables
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
    unset ALL_PROXY all_proxy NO_PROXY no_proxy
    
    log_debug "After unset - HTTP_PROXY: ${HTTP_PROXY:-'not set'}"
    log_success "Host proxy variables cleared"
}

clear_podman_machine_proxy() {
    if is_true "$USE_BUILD_PROXY"; then
        log_debug "Build proxy enabled, skipping Podman machine cleanup"
        return 0
    fi
    
    log_info "Clearing proxy settings in Podman machine..."
    
    # Check if podman machine exists
    if ! podman machine list &>/dev/null; then
        log_debug "No Podman machine found, skipping proxy cleanup"
        return 0
    fi
    
    # Try to unset proxy in Podman machine environment
    if podman machine ssh podman-machine-default \
        "sudo systemctl unset-environment HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy" \
        2>/dev/null; then
        log_success "Proxy settings cleared in Podman machine"
    else
        log_warning "Failed to clear proxy in Podman machine (this may be expected)"
    fi
}

# =====================================
# PROXY VALIDATION
# =====================================

validate_proxy_urls() {
    local urls=("$@")
    local invalid=()
    
    for url in "${urls[@]}"; do
        # Skip empty URLs
        [ -z "$url" ] && continue
        
        # Basic URL validation (starts with http:// or https://)
        if [[ ! "$url" =~ ^https?:// ]]; then
            invalid+=("$url")
        fi
    done
    
    if [ ${#invalid[@]} -gt 0 ]; then
        log_error "Invalid proxy URLs found:"
        for url in "${invalid[@]}"; do
            log_error "  - $url (must start with http:// or https://)"
        done
        return 1
    fi
    
    return 0
}

# =====================================
# PROXY INFO DISPLAY
# =====================================

print_proxy_config() {
    echo ""
    log_info "=== Proxy Configuration ==="
    
    # Build proxy
    if is_true "$USE_BUILD_PROXY"; then
        echo -e "${GREEN}Build Proxy: ENABLED${NC}"
        [ -n "$BUILD_HTTP_PROXY" ] && echo "  HTTP_PROXY:  $BUILD_HTTP_PROXY"
        [ -n "$BUILD_HTTPS_PROXY" ] && echo "  HTTPS_PROXY: $BUILD_HTTPS_PROXY"
        [ -n "$BUILD_NO_PROXY" ] && echo "  NO_PROXY:    $BUILD_NO_PROXY"
    else
        echo -e "${YELLOW}Build Proxy: DISABLED${NC}"
    fi
    
    echo ""
    
    # Runtime proxy
    if is_true "$USE_RUNTIME_PROXY"; then
        echo -e "${GREEN}Runtime Proxy: ENABLED${NC}"
        [ -n "$RUNTIME_HTTP_PROXY" ] && echo "  HTTP_PROXY:  $RUNTIME_HTTP_PROXY"
        [ -n "$RUNTIME_HTTPS_PROXY" ] && echo "  HTTPS_PROXY: $RUNTIME_HTTPS_PROXY"
        [ -n "$RUNTIME_NO_PROXY" ] && echo "  NO_PROXY:    $RUNTIME_NO_PROXY"
    else
        echo -e "${YELLOW}Runtime Proxy: DISABLED${NC}"
    fi
    
    echo ""
}

# =====================================
# MAIN EXECUTION
# =====================================

# If script is run directly (not sourced), display configuration
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Try to load environment if available
    if [ -f "$(dirname "$0")/../.env" ]; then
        # shellcheck source=lib/env-loader.sh
        source "$SCRIPT_DIR/env-loader.sh"
        load_env || exit 1
    fi
    
    print_proxy_config
fi