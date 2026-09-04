# Makefile for Mission Control Factorio Mod
# ==========================================

# Configuration
# --------------
MOD_DIR := mod
INFO_FILE := $(MOD_DIR)/info.json
DIST_DIR := dist

# Luacheck configuration
LUACHECK := $(shell which luacheck 2>/dev/null)
LUACHECK_CONFIG := .luacheckrc

# Extract mod name and version from info.json
MOD_NAME := $(shell jq -r .name $(INFO_FILE))
MOD_VERSION := $(shell jq -r .version $(INFO_FILE))
MOD_FULL_NAME := $(MOD_NAME)_$(MOD_VERSION)

# Platform detection for Factorio mod directory
UNAME_S := $(shell uname -s)
# APPDATA is set on Windows, and under WSL when exported via WSLENV. It takes
# precedence so a WSL build deploys to the Windows Factorio install.
# ?= so an explicit FACTORIO_MODS_DIR from the environment always wins.
ifdef APPDATA
    FACTORIO_MODS_DIR ?= $(APPDATA)/Factorio/mods
else ifeq ($(UNAME_S),Darwin)
    FACTORIO_MODS_DIR ?= $(HOME)/Library/Application Support/factorio/mods
else
    FACTORIO_MODS_DIR ?= $(HOME)/.factorio/mods
endif

# Targets
# -------

.PHONY: all help clean package localdeploy install uninstall check lint lint-strict lint-install check-luacheck ci

# Default target
all: help

# Help target
help:
	@echo "Mission Control Mod - Available targets:"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make package      - Create distributable mod package in dist/"
	@echo "  make localdeploy  - Deploy mod to local Factorio mods directory"
	@echo "  make install      - Alias for localdeploy"
	@echo "  make uninstall    - Remove mod from local Factorio mods directory"
	@echo ""
	@echo "Quality & Testing:"
	@echo "  make check        - Verify mod structure and info.json"
	@echo "  make lint         - Run luacheck on mod code"
	@echo "  make lint-strict  - Run luacheck with strict settings"
	@echo "  make lint-install - Install luacheck via luarocks"
	@echo "  make ci           - Run all checks (for CI/CD)"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make dev-info     - Show mod info and file structure"
	@echo "  make help         - Show this help message"
	@echo ""
	@echo "Current configuration:"
	@echo "  Mod name:         $(MOD_NAME)"
	@echo "  Mod version:      $(MOD_VERSION)"
	@echo "  Package name:     $(MOD_FULL_NAME).zip"
	@echo "  Factorio mods:    $(FACTORIO_MODS_DIR)"
	@echo "  Luacheck:         $(if $(LUACHECK),✓ installed,✗ not found (run 'make lint-install'))"
	@echo ""

# Check mod structure and info.json
check:
	@echo "Checking mod structure..."
	@test -f $(INFO_FILE) || (echo "Error: $(INFO_FILE) not found!" && exit 1)
	@test -n "$(MOD_NAME)" || (echo "Error: Could not extract mod name from $(INFO_FILE)" && exit 1)
	@test -n "$(MOD_VERSION)" || (echo "Error: Could not extract version from $(INFO_FILE)" && exit 1)
	@echo "✓ Mod name:    $(MOD_NAME)"
	@echo "✓ Mod version: $(MOD_VERSION)"
	@echo "✓ Package:     $(MOD_FULL_NAME).zip"

# Package mod for distribution
package: check clean
	@echo "Creating distributable package..."
	@mkdir -p $(DIST_DIR)/$(MOD_FULL_NAME)

	@echo "Copying mod files..."
	@cp -r $(MOD_DIR)/* $(DIST_DIR)/$(MOD_FULL_NAME)/

	@echo "Cleaning up development files from package..."
	@find $(DIST_DIR)/$(MOD_FULL_NAME) -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(DIST_DIR)/$(MOD_FULL_NAME) -name ".gitignore" -type f -delete 2>/dev/null || true
	@find $(DIST_DIR)/$(MOD_FULL_NAME) -name ".DS_Store" -type f -delete 2>/dev/null || true
	@find $(DIST_DIR)/$(MOD_FULL_NAME) -name "*.swp" -type f -delete 2>/dev/null || true
	@find $(DIST_DIR)/$(MOD_FULL_NAME) -name "*.swo" -type f -delete 2>/dev/null || true
	@find $(DIST_DIR)/$(MOD_FULL_NAME) -name "*~" -type f -delete 2>/dev/null || true

	@echo "Creating ZIP archive..."
	@cd $(DIST_DIR) && 7z a -r $(MOD_FULL_NAME).zip $(MOD_FULL_NAME) 
	@rm -rf $(DIST_DIR)/$(MOD_FULL_NAME)

	@echo ""
	@echo "✓ Package created: $(DIST_DIR)/$(MOD_FULL_NAME).zip"
	@ls -lh $(DIST_DIR)/$(MOD_FULL_NAME).zip

# Deploy mod to local Factorio mods directory (expanded, not zipped)
localdeploy: check
	@echo "Deploying mod to local Factorio directory..."
	@test -d "$(FACTORIO_MODS_DIR)" || (echo "Error: Factorio mods directory not found at $(FACTORIO_MODS_DIR)" && exit 1)

	@echo "Removing old version if exists..."
	@rm -rf "$(FACTORIO_MODS_DIR)/$(MOD_NAME)"
	@rm -f "$(FACTORIO_MODS_DIR)/$(MOD_NAME)_"*.zip

	@echo "Copying mod files to $(FACTORIO_MODS_DIR)/$(MOD_NAME)..."
	@mkdir -p "$(FACTORIO_MODS_DIR)/$(MOD_NAME)"
	@cp -r $(MOD_DIR)/* "$(FACTORIO_MODS_DIR)/$(MOD_NAME)/"

	@echo "Cleaning up development files..."
	@find "$(FACTORIO_MODS_DIR)/$(MOD_NAME)" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
	@find "$(FACTORIO_MODS_DIR)/$(MOD_NAME)" -name ".gitignore" -type f -delete 2>/dev/null || true
	@find "$(FACTORIO_MODS_DIR)/$(MOD_NAME)" -name ".DS_Store" -type f -delete 2>/dev/null || true

	@echo ""
	@echo "✓ Mod deployed to: $(FACTORIO_MODS_DIR)/$(MOD_NAME)"
	@echo "  Restart Factorio to load the updated mod"

# Alias for localdeploy
install: localdeploy

# Remove mod from local Factorio mods directory
uninstall:
	@echo "Uninstalling mod from local Factorio directory..."
	@test -d "$(FACTORIO_MODS_DIR)" || (echo "Error: Factorio mods directory not found at $(FACTORIO_MODS_DIR)" && exit 1)

	@rm -rf "$(FACTORIO_MODS_DIR)/$(MOD_NAME)"
	@rm -f "$(FACTORIO_MODS_DIR)/$(MOD_NAME)_"*.zip

	@echo "✓ Mod uninstalled"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DIST_DIR)
	@echo "✓ Clean complete"

# Linting and Quality Checks
# ---------------------------

# Check if luacheck is installed
check-luacheck:
	@if [ -z "$(LUACHECK)" ]; then \
		echo "Error: luacheck not found!"; \
		echo ""; \
		echo "Install luacheck with one of:"; \
		echo "  • make lint-install    (via luarocks)"; \
		echo "  • luarocks install luacheck"; \
		echo "  • apt install lua-check    (Debian/Ubuntu)"; \
		echo "  • brew install luacheck    (macOS)"; \
		echo ""; \
		exit 1; \
	fi

# Run luacheck on mod code
lint: check-luacheck
	@echo "Running luacheck on mod code..."
	@$(LUACHECK) $(MOD_DIR) --config $(LUACHECK_CONFIG)
	@echo ""
	@echo "✓ Lint check complete"

# Run luacheck with strict settings (no ignores)
lint-strict: check-luacheck
	@echo "Running strict luacheck (all warnings enabled)..."
	@$(LUACHECK) $(MOD_DIR) --config $(LUACHECK_CONFIG) --no-unused --no-redefined --no-unused-args
	@echo ""
	@echo "✓ Strict lint check complete"

# Install luacheck via luarocks
lint-install:
	@echo "Installing luacheck via luarocks..."
	@if ! which luarocks >/dev/null 2>&1; then \
		echo "Error: luarocks not found!"; \
		echo ""; \
		echo "Please install luarocks first:"; \
		echo "  • Debian/Ubuntu: apt install luarocks"; \
		echo "  • macOS: brew install luarocks"; \
		echo "  • Arch: pacman -S luarocks"; \
		echo ""; \
		exit 1; \
	fi
	@luarocks install --local luacheck
	@echo ""
	@echo "✓ Luacheck installed"
	@echo ""
	@echo "Add to your PATH (if needed):"
	@echo "  export PATH=\"\$$HOME/.luarocks/bin:\$$PATH\""

# CI target - run all checks
ci: check lint
	@echo ""
	@echo "✓ All CI checks passed"

# Development helpers
# --------------------

.PHONY: watch dev-info list-files

# Show current mod info
dev-info:
	@echo "Mod Information:"
	@echo "================"
	@cat $(INFO_FILE) | grep -E '(name|version|title|author)' | sed 's/^/  /'
	@echo ""
	@echo "File Structure:"
	@echo "==============="
	@find $(MOD_DIR) -type f ! -path "*/.git/*" | sort | sed 's|^$(MOD_DIR)/|  |'

# List all mod files
list-files:
	@find $(MOD_DIR) -type f ! -path "*/.git/*" | sort

# Quick test: package and install
.PHONY: test-install
test-install: package localdeploy
	@echo ""
	@echo "✓ Test install complete"
	@echo "  Package:  $(DIST_DIR)/$(MOD_FULL_NAME).zip"
	@echo "  Deployed: $(FACTORIO_MODS_DIR)/$(MOD_NAME)"
