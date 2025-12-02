#!/bin/bash
# =====================================
# SETUP-ENV.SH - Interactive .env Creation
# =====================================
# This script creates a .env file from .env.example through interactive prompts.
# It handles all configuration options including proxy settings and GHCR integration.
#
# Usage:
#   ./scripts/setup-env.sh
#
# Dependencies:
#   - lib/common.sh (for colors and logging)
#   - .env.example (template file)

set -e

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "$PROJECT_ROOT/make-app/lib/common.sh"

# =====================================
# CONFIGURATION
# =====================================
readonly ENV_FILE="$PROJECT_ROOT/.env"
readonly ENV_EXAMPLE="$PROJECT_ROOT/.env.example"

# =====================================
# HELPER FUNCTIONS
# =====================================

# Load defaults from .env.example
load_defaults_from_example() {
    if [ -f "$ENV_EXAMPLE" ]; then
        # Parse .env.example and create ENV_DEFAULT_* variables to avoid conflicts
        # with readonly variables from lib/common.sh
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove leading/trailing whitespace and quotes from value
            value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
            
            # Export as ENV_DEFAULT_* to avoid conflicts
            eval "ENV_DEFAULT_${key}='${value}'"
        done < "$ENV_EXAMPLE"
    fi
}

# Prompt user for a configuration value
# Arguments:
#   $1: Prompt text
#   $2: Default value (optional)
#   $3: Current value (optional, takes precedence over default)
# Returns:
#   User input or default/current value
prompt_config() {
    local prompt_text=$1
    local default_value=$2
    local current_value=$3
    
    # Determine display value
    if [ -n "$current_value" ]; then
        current_value=$current_value
    elif [ -n "$default_value" ]; then
        current_value=$default_value
    fi
    
    # Prompt with or without default
    if [ -n "$current_value" ]; then
        read -r -p "${prompt_text} [$current_value]: " input
        echo "${input:-$current_value}"
    else
        read -r -p "${prompt_text}: " input
        echo "$input"
    fi
}

# Prompt for yes/no question
# Arguments:
#   $1: Prompt text
# Returns:
#   0 if yes, 1 if no
prompt_yes_no() {
    local prompt_text=$1
    local response
    
    read -r -p "${prompt_text} (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# =====================================
# MAIN FUNCTIONS
# =====================================

# Check if .env.example exists
check_env_example() {
    if [ ! -f "$ENV_EXAMPLE" ]; then
        log_error ".env.example file not found at $ENV_EXAMPLE"
        exit 1
    fi
}

# Collect configuration through interactive prompts
collect_configuration() {
    # Load defaults from .env.example
    load_defaults_from_example
    
    print_header "Configuration Setup"
    echo ""
    log_info "Press Enter to accept default values shown in [brackets]"
    echo ""
    
    # Base configuration
    print_header "Base Configuration"
    CONTAINER_NAME=$(prompt_config "Container name" "${ENV_DEFAULT_CONTAINER_NAME:-happy-ttyd}" "")
    TTYD_PORT=$(prompt_config "Port" "${ENV_DEFAULT_TTYD_PORT:-7681}" "")
    TTYD_USER=$(prompt_config "User" "${ENV_DEFAULT_TTYD_USER:-root}" "")
    TTYD_FONTSIZE=$(prompt_config "TTYD font size" "16" "")
    
    # Build-time proxy configuration
    echo ""
    print_header "Build-time Proxy Configuration"
    if prompt_yes_no "Enable build-time proxy?"; then
        USE_BUILD_PROXY="true"
        BUILD_HTTP_PROXY=$(prompt_config "  HTTP proxy" "${ENV_DEFAULT_BUILD_HTTP_PROXY}" "")
        BUILD_HTTPS_PROXY=$(prompt_config "  HTTPS proxy" "${ENV_DEFAULT_BUILD_HTTPS_PROXY}" "")
        BUILD_NO_PROXY=$(prompt_config "  NO_PROXY" "${ENV_DEFAULT_BUILD_NO_PROXY:-localhost,127.0.0.1}" "")
    else
        USE_BUILD_PROXY="false"
        BUILD_HTTP_PROXY=""
        BUILD_HTTPS_PROXY=""
        BUILD_NO_PROXY=""
    fi
    
    # Node.js and packages configuration
    echo ""
    print_header "Node.js and Packages Configuration"
    NODE_VERSION=$(prompt_config "Node.js version" "${ENV_DEFAULT_NODE_VERSION:-24}" "")
    EXTRA_APK_PACKAGES=$(prompt_config "Extra APK packages (space-separated)" "${ENV_DEFAULT_EXTRA_APK_PACKAGES}" "")
    EXTRA_NPM_PACKAGES=$(prompt_config "Extra NPM packages (space-separated)" "${ENV_DEFAULT_EXTRA_NPM_PACKAGES}" "")
    
    # Runtime proxy configuration
    echo ""
    print_header "Runtime Proxy Configuration"
    if prompt_yes_no "Enable runtime proxy?"; then
        USE_RUNTIME_PROXY="true"
        RUNTIME_HTTP_PROXY=$(prompt_config "  HTTP proxy" "${ENV_DEFAULT_RUNTIME_HTTP_PROXY}" "")
        RUNTIME_HTTPS_PROXY=$(prompt_config "  HTTPS proxy" "${ENV_DEFAULT_RUNTIME_HTTPS_PROXY}" "")
        RUNTIME_NO_PROXY=$(prompt_config "  NO_PROXY" "${ENV_DEFAULT_RUNTIME_NO_PROXY:-localhost,127.0.0.1}" "")
    else
        USE_RUNTIME_PROXY="false"
        RUNTIME_HTTP_PROXY=""
        RUNTIME_HTTPS_PROXY=""
        RUNTIME_NO_PROXY=""
    fi
    
    # GitHub Container Registry configuration
    echo ""
    print_header "GitHub Container Registry Configuration"
    if prompt_yes_no "Enable GitHub Container Registry (ghcr.io)?"; then
        USE_GHCR="true"
        GHCR_USERNAME=$(prompt_config "  GitHub username" "${ENV_DEFAULT_GHCR_USERNAME}" "")
        GHCR_TOKEN=$(prompt_config "  GitHub personal access token" "${ENV_DEFAULT_GHCR_TOKEN}" "")
        GHCR_REPOSITORY=$(prompt_config "  Repository name" "${ENV_DEFAULT_GHCR_REPOSITORY:-happy-ttyd}" "")
    else
        USE_GHCR="false"
        GHCR_USERNAME=""
        GHCR_TOKEN=""
        GHCR_REPOSITORY="${ENV_DEFAULT_GHCR_REPOSITORY:-happy-ttyd}"
    fi
    
    # Happy Coder configuration (optional)
    echo ""
    print_header "Happy Coder Configuration (Optional)"
    ANTHROPIC_BASE_URL=$(prompt_config "Anthropic Base URL" "${ENV_DEFAULT_ANTHROPIC_BASE_URL}" "")
    ANTHROPIC_AUTH_TOKEN=$(prompt_config "Anthropic Auth Token" "${ENV_DEFAULT_ANTHROPIC_AUTH_TOKEN}" "")
    ANTHROPIC_MODEL=$(prompt_config "Anthropic Model" "${ENV_DEFAULT_ANTHROPIC_MODEL}" "")
    ANTHROPIC_SMALL_FAST_MODEL=$(prompt_config "Anthropic Small Fast Model" "${ENV_DEFAULT_ANTHROPIC_SMALL_FAST_MODEL}" "")
    
    # MCP Server configuration
    echo ""
    print_header "MCP Server Configuration"
    if prompt_yes_no "Enable MCP server installation?"; then
        INSTALL_MCP_SERVERS="true"
        MCP_SERVER_REPOS=$(prompt_config "  MCP server repositories (space-separated URLs)" "${ENV_DEFAULT_MCP_SERVER_REPOS}" "")
        MCP_SERVER_BASE_PATH=$(prompt_config "  MCP server base path" "${ENV_DEFAULT_MCP_SERVER_BASE_PATH:-/mcp-server}" "")
    else
        INSTALL_MCP_SERVERS="false"
        MCP_SERVER_REPOS=""
        MCP_SERVER_BASE_PATH="${ENV_DEFAULT_MCP_SERVER_BASE_PATH:-/mcp-server}"
    fi
}

# Write collected configuration to .env file
write_env_file() {
    log_info "Saving configuration to .env..."
    
    cat > "$ENV_FILE" << EOF
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

# ===== HAPPY CODER CONFIGURATION =====
# Configuration for Happy Coder (Anthropic API)
ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN
ANTHROPIC_MODEL=$ANTHROPIC_MODEL
ANTHROPIC_SMALL_FAST_MODEL=$ANTHROPIC_SMALL_FAST_MODEL

# ===== MCP SERVER CONFIGURATION =====
# Enable MCP server installation in container
INSTALL_MCP_SERVERS=$INSTALL_MCP_SERVERS
MCP_SERVER_REPOS="$MCP_SERVER_REPOS"
MCP_SERVER_BASE_PATH=$MCP_SERVER_BASE_PATH
EOF
    
    log_success "Configuration saved to .env"
}

# Display next steps to the user
show_next_steps() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    log_success "Setup Complete!"
    echo ""
    log_info "Next steps:"
    echo -e "  1. Review your configuration:"
    echo -e "     ${YELLOW}cat .env${NC}"
    echo ""
    echo -e "  2. Generate build files:"
    echo -e "     ${YELLOW}make generate-all${NC}"
    echo ""
    echo -e "  3. Build the container:"
    echo -e "     ${YELLOW}make build${NC}"
    echo ""
    echo -e "  4. Start the container:"
    echo -e "     ${YELLOW}make up${NC}"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# =====================================
# MAIN EXECUTION
# =====================================

main() {
    # Verify .env.example exists first
    check_env_example
    
    # Check if .env already exists
    if [ -f "$ENV_FILE" ]; then
        # If .env exists, open it in vim for editing
        log_info ".env file found - opening in vim for editing"
        vim "$ENV_FILE"
        log_success "Configuration updated"
        echo ""
        log_info "Next steps:"
        echo -e "  1. Generate build files: ${YELLOW}make generate-all${NC}"
        echo -e "  2. Build container: ${YELLOW}make build${NC}"
        exit 0
    else
        # If .env doesn't exist, run interactive prompts with defaults from .env.example
        log_info "No .env file found - starting interactive configuration"
    fi
    
    # Collect configuration through interactive prompts
    collect_configuration
    
    # Write configuration to .env
    write_env_file
    
    # Show next steps
    show_next_steps
}

# Run main function
main "$@"