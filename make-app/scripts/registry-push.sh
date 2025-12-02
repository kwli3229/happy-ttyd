#!/bin/bash
# =====================================
# REGISTRY-PUSH.SH - Container Registry Operations
# =====================================
# This script handles authentication and pushing to GitHub Container Registry (ghcr.io).
# It tags the local image and pushes it to the configured registry.
#
# Usage:
#   ./scripts/registry-push.sh
#
# Dependencies:
#   - lib/common.sh (for colors and logging)
#   - lib/env-loader.sh (for .env loading)
#   - Built container image (from build-image.sh)

set -e

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "$PROJECT_ROOT/make-app/lib/common.sh"
# shellcheck source=../lib/env-loader.sh
source "$PROJECT_ROOT/make-app/lib/env-loader.sh"

# =====================================
# HELPER FUNCTIONS
# =====================================

# Check if GHCR is enabled
check_ghcr_enabled() {
    if [ "$USE_GHCR" != "true" ]; then
        log_warning "GitHub Container Registry is not enabled"
        log_info "Set USE_GHCR=true in .env to enable GHCR push"
        exit 0
    fi
}

# Generate version tag from git hash, GHCR_TAG, or timestamp
generate_version_tag() {
    local version_tag
    
    # Try to get git hash (short form)
    if command -v git &> /dev/null && git rev-parse --short HEAD &> /dev/null; then
        version_tag=$(git rev-parse --short HEAD)
        log_debug "Using git hash as version: $version_tag"
    # Use GHCR_TAG if set
    elif [ -n "${GHCR_TAG:-}" ]; then
        version_tag="$GHCR_TAG"
        log_debug "Using GHCR_TAG as version: $version_tag"
    # Fall back to timestamp
    else
        version_tag=$(date +%Y%m%d-%H%M%S)
        log_debug "Using timestamp as version: $version_tag"
    fi
    
    echo "$version_tag"
}

# Check if local image exists
check_local_image() {
    log_info "Checking for local image: ${CONTAINER_NAME}"
    
    if ! podman image exists "${CONTAINER_NAME}"; then
        log_error "Local image '${CONTAINER_NAME}' not found"
        log_info "Build the image first with: make build"
        exit 1
    fi
    
    log_success "Local image found"
}

# Authenticate with GitHub Container Registry
authenticate_ghcr() {
    log_info "Authenticating with GitHub Container Registry..."
    echo ""
    
    # Login to ghcr.io using podman
    if echo "$GHCR_TOKEN" | podman login ghcr.io -u "$GHCR_USERNAME" --password-stdin; then
        log_success "Authentication successful"
        return 0
    else
        log_error "Authentication failed"
        log_info "Please check your GHCR_USERNAME and GHCR_TOKEN in .env"
        return 1
    fi
}

# Tag the local image for GHCR with both versioned and latest tags
tag_image() {
    local version_tag=$(generate_version_tag)
    local versioned_tag="ghcr.io/$GHCR_USERNAME/$GHCR_REPOSITORY:$version_tag"
    local latest_tag="ghcr.io/$GHCR_USERNAME/$GHCR_REPOSITORY:latest"
    
    log_info "Tagging image for GHCR..." >&2
    log_debug "Source: ${CONTAINER_NAME}" >&2
    log_debug "Versioned tag: ${versioned_tag}" >&2
    log_debug "Latest tag: ${latest_tag}" >&2
    echo "" >&2
    
    # Tag with version
    if ! podman tag "$CONTAINER_NAME" "$versioned_tag" >&2; then
        log_error "Failed to tag image with version" >&2
        return 1
    fi
    
    # Tag with latest
    if ! podman tag "$CONTAINER_NAME" "$latest_tag" >&2; then
        log_error "Failed to tag image with latest" >&2
        return 1
    fi
    
    log_success "Image tagged successfully" >&2
    
    # Return both tags (space-separated for parsing) - ONLY stdout
    echo "$versioned_tag $latest_tag"
    return 0
}

# Push image to GHCR (handles both versioned and latest tags)
push_image() {
    local versioned_tag=$1
    local latest_tag=$2
    
    log_info "Pushing versioned image to GHCR..."
    echo -e "  Tag: ${BLUE}${versioned_tag}${NC}"
    echo ""
    
    if ! podman push "$versioned_tag"; then
        log_error "Failed to push versioned tag"
        return 1
    fi
    
    log_success "Versioned image pushed successfully"
    echo ""
    
    log_info "Pushing latest image to GHCR..."
    echo -e "  Tag: ${BLUE}${latest_tag}${NC}"
    echo ""
    
    if ! podman push "$latest_tag"; then
        log_error "Failed to push latest tag"
        return 1
    fi
    
    log_success "Latest image pushed successfully"
    return 0
}

# Display success message
show_success() {
    local versioned_tag=$1
    local latest_tag=$2
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_success "Push Complete!"
    echo ""
    
    log_info "Images published to GHCR:"
    echo -e "  Versioned: ${BLUE}${versioned_tag}${NC}"
    echo -e "  Latest:    ${BLUE}${latest_tag}${NC}"
    echo ""
    
    log_info "Pull commands:"
    echo -e "  ${YELLOW}podman pull ${versioned_tag}${NC}"
    echo -e "  ${YELLOW}podman pull ${latest_tag}${NC}"
    echo ""
    
    log_info "View on GitHub:"
    echo -e "  ${YELLOW}https://github.com/${GHCR_USERNAME}/${GHCR_REPOSITORY}/pkgs/container/${GHCR_REPOSITORY}${NC}"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Display failure message
show_failure() {
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_error "Push Failed"
    echo ""
    
    log_info "Debug Information:"
    echo "  Container name: ${CONTAINER_NAME}"
    echo "  GHCR username: ${GHCR_USERNAME}"
    echo "  GHCR repository: ${GHCR_REPOSITORY}"
    echo ""
    
    log_info "Common issues:"
    echo "  1. Invalid GitHub personal access token"
    echo "  2. Token missing required permissions (write:packages)"
    echo "  3. Network connectivity issues"
    echo "  4. Repository doesn't exist or access denied"
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =====================================
# MAIN EXECUTION
# =====================================

main() {
    print_header "GitHub Container Registry Push"
    
    # Load and validate environment
    load_and_validate_env
    
    # Check if GHCR is enabled
    check_ghcr_enabled
    
    # Check if local image exists
    check_local_image
    
    # Authenticate with GHCR
    if ! authenticate_ghcr; then
        exit 1
    fi
    
    echo ""
    
    # Tag the image (returns "versioned_tag latest_tag")
    local tags
    if ! tags=$(tag_image); then
        show_failure
        exit 1
    fi
    
    # Split tags into versioned and latest
    local versioned_tag=$(echo "$tags" | awk '{print $1}')
    local latest_tag=$(echo "$tags" | awk '{print $2}')
    
    echo ""
    
    # Push the images
    if push_image "$versioned_tag" "$latest_tag"; then
        show_success "$versioned_tag" "$latest_tag"
        exit 0
    else
        show_failure
        exit 1
    fi
}

# Run main function
main "$@"