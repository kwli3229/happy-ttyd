# Makefile for ttyd Web Terminal Container
# Provides targets for build, deploy, compose, and maintenance operations

# Load environment variables
include .env
export

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

# Phony targets
.PHONY: help setup build deploy deploy-with-env stop start restart logs shell clean clean-all compose-up compose-down compose-restart status rebuild

##@ Help

help: ## Display this help message
	@echo ""
	@echo "$(GREEN)ttyd Web Terminal Container - Makefile$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(GREEN)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

##@ Setup

setup: ## Initialize .env file if it doesn't exist
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)Creating .env from .env.example...$(NC)"; \
		cp .env.example .env; \
		echo "$(GREEN)✓ .env file created. Please edit it with your configuration.$(NC)"; \
	else \
		echo "$(GREEN)✓ .env file already exists.$(NC)"; \
	fi

##@ Build

build: ## Build the container image
	@echo "$(GREEN)Building container image...$(NC)"
	@./build.sh
	@echo "$(GREEN)✓ Build complete!$(NC)"

rebuild: clean build ## Clean and rebuild the container image

generate-podmanfile: ## Generate Podmanfile without building
	@echo "$(YELLOW)Generating Podmanfile...$(NC)"
	@bash -c 'source .env && bash -c "source build.sh; generate_podmanfile"' 2>/dev/null || ./build.sh
	@echo "$(GREEN)✓ Podmanfile generated$(NC)"

generate-compose: ## Generate podman-compose.yml without building
	@echo "$(YELLOW)Generating podman-compose.yml...$(NC)"
	@if [ ! -f .env ]; then \
		echo "$(RED)Error: .env file not found. Run 'make setup' first.$(NC)"; \
		exit 1; \
	fi
	@bash -c 'source .env && source build.sh && generate_compose_file'
	@echo "$(GREEN)✓ podman-compose.yml generated$(NC)"

generate-all: ## Generate both Podmanfile and podman-compose.yml
	@$(MAKE) generate-podmanfile
	@$(MAKE) generate-compose

##@ Deploy

deploy: ## Deploy container with environment variables
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

deploy-with-volume: ## Deploy container with workspace volume mount
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

##@ Compose

compose-up: ## Start services using podman-compose
	@echo "$(GREEN)Starting services with podman-compose...$(NC)"
	@podman-compose -f podman-compose.yml up -d
	@echo "$(GREEN)✓ Services started!$(NC)"
	@echo "$(GREEN)Access at: $(YELLOW)http://localhost:$(TTYD_PORT)$(NC)"

compose-down: ## Stop services using podman-compose
	@echo "$(YELLOW)Stopping services...$(NC)"
	@podman-compose -f podman-compose.yml down
	@echo "$(GREEN)✓ Services stopped!$(NC)"

compose-restart: ## Restart services using podman-compose
	@echo "$(YELLOW)Restarting services...$(NC)"
	@podman-compose -f podman-compose.yml restart
	@echo "$(GREEN)✓ Services restarted!$(NC)"

compose-logs: ## View podman-compose logs
	@podman-compose -f podman-compose.yml logs -f

##@ Container Management

start: ## Start the container
	@echo "$(GREEN)Starting container: $(CONTAINER_NAME)$(NC)"
	@podman start $(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container started!$(NC)"

stop: ## Stop the container
	@echo "$(YELLOW)Stopping container: $(CONTAINER_NAME)$(NC)"
	@podman stop $(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container stopped!$(NC)"

restart: ## Restart the container
	@echo "$(YELLOW)Restarting container: $(CONTAINER_NAME)$(NC)"
	@podman restart $(CONTAINER_NAME)
	@echo "$(GREEN)✓ Container restarted!$(NC)"

status: ## Show container status
	@echo "$(GREEN)Container Status:$(NC)"
	@podman ps -a --filter name=$(CONTAINER_NAME)
	@echo ""
	@echo "$(GREEN)Environment Variables:$(NC)"
	@if podman ps --filter name=$(CONTAINER_NAME) --format "{{.Names}}" | grep -q "^$(CONTAINER_NAME)$$"; then \
		podman exec $(CONTAINER_NAME) env | grep ANTHROPIC || echo "$(YELLOW)No ANTHROPIC variables set$(NC)"; \
	else \
		echo "$(RED)Container is not running$(NC)"; \
	fi

logs: ## View container logs
	@podman logs -f $(CONTAINER_NAME)

shell: ## Access container shell
	@echo "$(GREEN)Accessing container shell...$(NC)"
	@podman exec -it $(CONTAINER_NAME) bash

##@ Maintenance

clean: ## Remove container and generated files
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

clean-all: clean ## Remove container, image, and generated files
	@echo "$(YELLOW)Removing image: $(CONTAINER_NAME)$(NC)"
	@podman rmi -f $(CONTAINER_NAME) 2>/dev/null || true
	@echo "$(GREEN)✓ Full cleanup complete!$(NC)"

prune: ## Remove unused containers and images
	@echo "$(YELLOW)Pruning unused containers...$(NC)"
	@podman container prune -f
	@echo "$(YELLOW)Pruning unused images...$(NC)"
	@podman image prune -f
	@echo "$(GREEN)✓ Prune complete!$(NC)"

update-deps: ## Update container dependencies (rebuild with latest packages)
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	@$(MAKE) clean-all
	@$(MAKE) build
	@echo "$(GREEN)✓ Dependencies updated!$(NC)"

backup-env: ## Backup .env file
	@echo "$(YELLOW)Backing up .env file...$(NC)"
	@cp .env .env.backup.$$(date +%Y%m%d_%H%M%S)
	@echo "$(GREEN)✓ Backup created!$(NC)"

##@ Convenience Targets

all: setup build deploy ## Setup, build, and deploy in one command

dev: build deploy-with-volume logs ## Build, deploy with volume, and show logs

up: deploy ## Alias for deploy

down: stop ## Alias for stop

ps: status ## Alias for status