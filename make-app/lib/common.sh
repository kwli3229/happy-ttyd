#!/bin/bash
# lib/common.sh - Shared utilities and constants for build system
# This library provides common functions and constants used across all scripts

# Prevent multiple sourcing
if [ -n "${_COMMON_SH_LOADED:-}" ]; then
    return 0
fi
readonly _COMMON_SH_LOADED=1

# =====================================
# COLOR CONSTANTS
# =====================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =====================================
# BUILD CONSTANTS
# =====================================
readonly DEFAULT_ALPINE_VERSION="${ALPINE_VERSION:-latest}"
readonly DEFAULT_NODE_VERSION="${NODE_VERSION:-24}"
readonly DEFAULT_TTYD_PORT="${TTYD_PORT:-7681}"

# Path constants
readonly SCRIPTS_DIR="conf/entrypoint"
readonly ENTRYPOINT_SCRIPT="entrypoint.sh"

# Build stage packages
readonly BUILD_PACKAGES=(
    "nodejs"
    "npm"
)

# Runtime stage core packages
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

# =====================================
# LOGGING FUNCTIONS
# =====================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${YELLOW}[DEBUG]${NC} $*"
    fi
}

# =====================================
# ERROR HANDLING
# =====================================

die() {
    log_error "$*"
    exit 1
}

check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        die "Required command '$cmd' not found. Please install it first."
    fi
}

# =====================================
# UTILITY FUNCTIONS
# =====================================

# Check if a variable is set and not empty
is_set() {
    local var_name=$1
    [[ -n "${!var_name}" ]]
}

# Check if a boolean flag is true
is_true() {
    local value=$1
    [[ "$value" == "true" ]]
}

# Print a section header
print_header() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}$*${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Get script directory (useful for sourcing relative paths)
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# Get project root directory
get_project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}