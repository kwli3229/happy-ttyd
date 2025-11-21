#!/bin/bash
# lib/env-loader.sh - Load and validate .env configuration
# This library handles loading environment configuration from .env file

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common utilities
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"

# =====================================
# ENV LOADING
# =====================================

load_env() {
    local env_file="${PROJECT_ROOT}/.env"
    
    if [ ! -f "$env_file" ]; then
        log_error ".env file not found at: $env_file"
        log_info "Run 'make setup' to create one, or copy from .env.example"
        return 1
    fi
    
    log_debug "Loading configuration from .env"
    
    # Source the .env file
    # shellcheck source=../.env
    set -a  # Automatically export all variables
    source "$env_file"
    set +a
    
    log_debug "Configuration loaded successfully"
    return 0
}

# =====================================
# ENV VALIDATION
# =====================================

validate_required_vars() {
    local missing_vars=()
    
    # Check required variables
    if [ -z "$CONTAINER_NAME" ]; then
        missing_vars+=("CONTAINER_NAME")
    fi
    
    if [ -z "$TTYD_PORT" ]; then
        missing_vars+=("TTYD_PORT")
    fi
    
    # Report missing variables
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required variables in .env:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        return 1
    fi
    
    log_debug "All required variables are set"
    return 0
}

validate_proxy_config() {
    # Validate build proxy configuration
    if is_true "$USE_BUILD_PROXY"; then
        log_debug "Build proxy enabled, checking configuration..."
        
        if [ -z "$BUILD_HTTP_PROXY" ] && [ -z "$BUILD_HTTPS_PROXY" ]; then
            log_warning "USE_BUILD_PROXY=true but no proxy URLs configured"
            log_warning "Set BUILD_HTTP_PROXY and/or BUILD_HTTPS_PROXY in .env"
        fi
    fi
    
    # Validate runtime proxy configuration
    if is_true "$USE_RUNTIME_PROXY"; then
        log_debug "Runtime proxy enabled, checking configuration..."
        
        if [ -z "$RUNTIME_HTTP_PROXY" ] && [ -z "$RUNTIME_HTTPS_PROXY" ]; then
            log_warning "USE_RUNTIME_PROXY=true but no proxy URLs configured"
            log_warning "Set RUNTIME_HTTP_PROXY and/or RUNTIME_HTTPS_PROXY in .env"
        fi
    fi
}

validate_ghcr_config() {
    if is_true "$USE_GHCR"; then
        log_debug "GHCR enabled, checking configuration..."
        
        local missing=()
        [ -z "$GHCR_USERNAME" ] && missing+=("GHCR_USERNAME")
        [ -z "$GHCR_TOKEN" ] && missing+=("GHCR_TOKEN")
        [ -z "$GHCR_REPOSITORY" ] && missing+=("GHCR_REPOSITORY")
        
        if [ ${#missing[@]} -gt 0 ]; then
            log_error "USE_GHCR=true but missing required variables:"
            for var in "${missing[@]}"; do
                log_error "  - $var"
            done
            return 1
        fi
    fi
    
    return 0
}

validate_env() {
    log_debug "Validating environment configuration..."
    
    validate_required_vars || return 1
    validate_proxy_config
    validate_ghcr_config || return 1
    
    log_debug "Environment validation complete"
    return 0
}

# =====================================
# DEBUG INFO
# =====================================

print_env_debug() {
    if [ "${DEBUG:-false}" != "true" ]; then
        return
    fi
    
    log_debug "=== Environment Configuration ==="
    log_debug "CONTAINER_NAME: ${CONTAINER_NAME:-'not set'}"
    log_debug "TTYD_PORT: ${TTYD_PORT:-'not set'}"
    log_debug "NODE_VERSION: ${NODE_VERSION:-'not set'}"
    log_debug ""
    log_debug "=== Build Proxy ==="
    log_debug "USE_BUILD_PROXY: ${USE_BUILD_PROXY:-'not set'}"
    log_debug "BUILD_HTTP_PROXY: ${BUILD_HTTP_PROXY:-'not set'}"
    log_debug "BUILD_HTTPS_PROXY: ${BUILD_HTTPS_PROXY:-'not set'}"
    log_debug "BUILD_NO_PROXY: ${BUILD_NO_PROXY:-'not set'}"
    log_debug ""
    log_debug "=== Runtime Proxy ==="
    log_debug "USE_RUNTIME_PROXY: ${USE_RUNTIME_PROXY:-'not set'}"
    log_debug "RUNTIME_HTTP_PROXY: ${RUNTIME_HTTP_PROXY:-'not set'}"
    log_debug "RUNTIME_HTTPS_PROXY: ${RUNTIME_HTTPS_PROXY:-'not set'}"
    log_debug "RUNTIME_NO_PROXY: ${RUNTIME_NO_PROXY:-'not set'}"
    log_debug ""
    log_debug "=== GHCR ==="
    log_debug "USE_GHCR: ${USE_GHCR:-'not set'}"
    log_debug "GHCR_USERNAME: ${GHCR_USERNAME:-'not set'}"
    log_debug "GHCR_REPOSITORY: ${GHCR_REPOSITORY:-'not set'}"
    log_debug "=================================="
}

# =====================================
# MAIN FUNCTION
# =====================================

# Load and validate environment
load_and_validate_env() {
    load_env || return 1
    validate_env || return 1
    print_env_debug
    return 0
}

# If script is run directly (not sourced), load and validate
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    load_and_validate_env
    if [ $? -eq 0 ]; then
        log_success "Environment configuration is valid"
        exit 0
    else
        log_error "Environment configuration validation failed"
        exit 1
    fi
fi