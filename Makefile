# Makefile for ttyd Web Terminal Container
# Provides targets for build, deploy, compose, and maintenance operations

# Load environment variables (optional, won't fail if .env doesn't exist)
-include .env
export

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

# Phony targets
.PHONY: help setup generate-podmanfile generate-compose generate-all build rebuild push-to-ghcr \
        deploy deploy-with-volume compose-up compose-down compose-restart compose-logs \
        start stop restart status logs shell clean clean-all prune

##@ General

help: ## Display this help message
	@echo ""
	@echo "$(GREEN)ttyd Web Terminal Container - Makefile$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-24s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(GREEN)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

setup: ## Create/edit .env configuration file
	@./make-app/scripts/setup-env.sh

##@ Build

generate-podmanfile: ## Generate Podmanfile from .env
	@./make-app/scripts/generate-podmanfile.sh

generate-compose: ## Generate podman-compose.yml from .env
	@./make-app/scripts/generate-compose.sh

generate-all: ## Generate both Podmanfile and compose file
	@./make-app/scripts/generate-podmanfile.sh
	@./make-app/scripts/generate-compose.sh

build: ## Generate files and build container image
	@./make-app/scripts/generate-podmanfile.sh
	@./make-app/scripts/generate-compose.sh
	@./make-app/scripts/build-image.sh

rebuild: clean build ## Clean and rebuild container image

push-to-ghcr: ## Push image to GitHub Container Registry
	@./make-app/scripts/registry-push.sh

##@ Deploy (Direct Podman)

deploy: ## Deploy with podman run (no volumes)
	@echo "$(GREEN)Deploying container: $(CONTAINER_NAME)$(NC)"
	@if podman ps -a --format "{{.Names}}" | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "$(YELLOW)Removing existing container...$(NC)"; \
		podman rm -f $(CONTAINER_NAME); \
	fi
	@podman run -d \
		-p $(TTYD_PORT):7681 \
		$(if $(ANTHROPIC_BASE_URL),-e ANTHROPIC_BASE_URL='$(ANTHROPIC_BASE_URL)',) \
		$(if $(ANTHROPIC_AUTH_TOKEN),-e ANTHROPIC_AUTH_TOKEN='$(ANTHROPIC_AUTH_TOKEN)',) \
		$(if $(ANTHROPIC_MODEL),-e ANTHROPIC_MODEL='$(ANTHROPIC_MODEL)',) \
		$(if $(ANTHROPIC_SMALL_FAST_MODEL),-e ANTHROPIC_SMALL_FAST_MODEL='$(ANTHROPIC_SMALL_FAST_MODEL)',) \
		--name $(CONTAINER_NAME) \
		$(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container deployed!$(NC)"
	@echo "$(GREEN)Access at: $(YELLOW)http://localhost:$(TTYD_PORT)$(NC)"

deploy-with-volume: ## Deploy with workspace volume mount
	@echo "$(GREEN)Deploying container with volume: $(CONTAINER_NAME)$(NC)"
	@if podman ps -a --format "{{.Names}}" | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "$(YELLOW)Removing existing container...$(NC)"; \
		podman rm -f $(CONTAINER_NAME); \
	fi
	@mkdir -p ./workspace
	@podman run -d \
		-p $(TTYD_PORT):7681 \
		-v $(PWD)/workspace:/workspace \
		$(if $(ANTHROPIC_BASE_URL),-e ANTHROPIC_BASE_URL='$(ANTHROPIC_BASE_URL)',) \
		$(if $(ANTHROPIC_AUTH_TOKEN),-e ANTHROPIC_AUTH_TOKEN='$(ANTHROPIC_AUTH_TOKEN)',) \
		$(if $(ANTHROPIC_MODEL),-e ANTHROPIC_MODEL='$(ANTHROPIC_MODEL)',) \
		$(if $(ANTHROPIC_SMALL_FAST_MODEL),-e ANTHROPIC_SMALL_FAST_MODEL='$(ANTHROPIC_SMALL_FAST_MODEL)',) \
		--name $(CONTAINER_NAME) \
		$(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container deployed with volume!$(NC)"
	@echo "$(GREEN)Access at: $(YELLOW)http://localhost:$(TTYD_PORT)$(NC)"

##@ Compose (Recommended)

compose-up: ## Start services with podman-compose
	@echo "$(GREEN)Starting services with podman-compose...$(NC)"
	@podman-compose -f podman-compose.yml up -d
	@echo "$(GREEN)✓ Services started!$(NC)"
	@echo "$(GREEN)Access at: $(YELLOW)http://localhost:$(TTYD_PORT)$(NC)"

compose-down: ## Stop and remove compose services
	@echo "$(YELLOW)Stopping services...$(NC)"
	@podman-compose -f podman-compose.yml down
	@echo "$(GREEN)✓ Services stopped!$(NC)"

compose-restart: ## Restart compose services
	@echo "$(YELLOW)Restarting services...$(NC)"
	@podman-compose -f podman-compose.yml restart
	@echo "$(GREEN)✓ Services restarted!$(NC)"

compose-logs: ## View compose service logs (follow)
	@podman-compose -f podman-compose.yml logs -f

##@ Container Management

start: ## Start existing container
	@echo "$(GREEN)Starting container: $(CONTAINER_NAME)$(NC)"
	@podman start $(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container started!$(NC)"

stop: ## Stop running container
	@echo "$(YELLOW)Stopping container: $(CONTAINER_NAME)$(NC)"
	@podman stop $(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container stopped!$(NC)"

restart: ## Restart container
	@echo "$(YELLOW)Restarting container: $(CONTAINER_NAME)$(NC)"
	@podman restart $(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container restarted!$(NC)"

status: ## Show container status and env vars
	@echo "$(GREEN)Container Status:$(NC)"
	@podman ps -a --filter name=$(CONTAINER_NAME)
	@echo ""
	@echo "$(GREEN)Environment Variables:$(NC)"
	@if podman ps --filter name=$(CONTAINER_NAME) --format "{{.Names}}" | grep -q "^$(CONTAINER_NAME)$$"; then \
		podman exec $(CONTAINER_NAME) env | grep ANTHROPIC || echo "$(YELLOW)No ANTHROPIC variables set$(NC)"; \
	else \
		echo "$(RED)Container is not running$(NC)"; \
	fi

logs: ## View container logs (follow)
	@podman logs -f $(CONTAINER_NAME)

shell: ## Open bash shell in container
	@echo "$(GREEN)Accessing container shell...$(NC)"
	@podman exec -it $(CONTAINER_NAME) bash

##@ Maintenance

clean: ## Remove container + generated files
	@echo "$(YELLOW)Cleaning up...$(NC)"
	@if podman ps -a --format "{{.Names}}" | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "$(YELLOW)Removing container: $(CONTAINER_NAME)$(NC)"; \
		podman rm -f $(CONTAINER_NAME); \
	fi
	@if [ -f Podmanfile ]; then \
		echo "$(YELLOW)Removing generated Podmanfile$(NC)"; \
		rm -f Podmanfile; \
	fi
	@if [ -f podman-compose.yml ]; then \
		echo "$(YELLOW)Removing generated podman-compose.yml$(NC)"; \
		rm -f podman-compose.yml; \
	fi
	@echo "$(GREEN)✓ Cleanup complete!$(NC)"

clean-all: clean ## Remove container + image + generated files + .env
	@echo "$(YELLOW)Removing image: $(CONTAINER_NAME)$(NC)"
	@podman rmi -f $(CONTAINER_NAME) 2>/dev/null || true
	@if [ -f .env ]; then \
		echo "$(YELLOW)Removing .env file$(NC)"; \
		rm -f .env; \
	fi
	@echo "$(GREEN)✓ Full cleanup complete!$(NC)"

prune: ## Remove all unused containers and images
	@echo "$(YELLOW)Pruning unused containers...$(NC)"
	@podman container prune -f
	@echo "$(YELLOW)Pruning unused images...$(NC)"
	@podman image prune -f
	@echo "$(GREEN)✓ Prune complete!$(NC)"

##@ Convenience Aliases

up: compose-up ## Alias: compose-up

down: compose-down ## Alias: compose-down

ps: status ## Alias: status