# NixOS Router Configuration Makefile
#
# Usage:
#   make decrypt  - Decrypt private/config.nix.age to private/config.nix
#   make encrypt  - Encrypt private/config.nix to private/config.nix.age
#   make verify   - Verify encrypted file matches decrypted (for pre-commit)
#   make build    - Build the NixOS configuration
#   make switch   - Switch to the new configuration
#   make clean    - Remove decrypted config

# Configuration - update these paths if needed
AGE_KEY := /etc/ssh/ssh_host_ed25519_key
AGE_RECIPIENT := /etc/ssh/ssh_host_ed25519_key.pub

# Private config locations
PRIVATE_DIR := private
PRIVATE_CONFIG := $(PRIVATE_DIR)/config.nix
PRIVATE_CONFIG_AGE := $(PRIVATE_DIR)/config.nix.age

.PHONY: decrypt encrypt verify build switch test clean help init check check-verbose lint diff-config

help:
	@echo "Available targets:"
	@echo "  init     - Initialize private/ directory and install pre-commit hooks"
	@echo "  decrypt  - Decrypt private/config.nix.age to private/config.nix"
	@echo "  encrypt  - Encrypt private/config.nix to private/config.nix.age"
	@echo "  diff-config - Show changes to private/config.nix before encrypting"
	@echo "  verify   - Verify encrypted file matches decrypted"
	@echo "  build    - Build the NixOS configuration"
	@echo "  switch   - Switch to the new configuration"
	@echo "  test     - Test the new configuration (nixos-rebuild test)"
	@echo "  check    - Run all tests via nix flake check"
	@echo "  check-verbose - Run flake check with verbose output"
	@echo "  lint     - Run pre-commit hooks on all files"
	@echo "  clean    - Remove decrypted config"

# Initialize private directory from example and install pre-commit hooks
init:
	@if [ -d $(PRIVATE_DIR) ]; then \
		echo "$(PRIVATE_DIR)/ already exists"; \
	else \
		cp -r private.example $(PRIVATE_DIR); \
		echo "✓ Created $(PRIVATE_DIR)/ from private.example/"; \
		echo "  Edit $(PRIVATE_CONFIG) with your values"; \
	fi
	@uvx pre-commit install && echo "✓ Installed pre-commit hooks"

# Decrypt private/config.nix.age to private/config.nix
decrypt:
	@if [ -f $(PRIVATE_CONFIG_AGE) ]; then \
		age -d -i $(AGE_KEY) $(PRIVATE_CONFIG_AGE) > $(PRIVATE_CONFIG); \
		echo "✓ Decrypted $(PRIVATE_CONFIG)"; \
	else \
		echo "No $(PRIVATE_CONFIG_AGE) found."; \
		if [ ! -f $(PRIVATE_CONFIG) ]; then \
			echo "Run 'make init' to create private/ from the example"; \
		fi; \
	fi

# Encrypt private/config.nix to private/config.nix.age
encrypt:
	@if [ -f $(PRIVATE_CONFIG) ]; then \
		age -e -R $(AGE_RECIPIENT) -o $(PRIVATE_CONFIG_AGE) $(PRIVATE_CONFIG) || \
			(echo "ERROR: age encryption failed - is age installed?"; exit 1); \
		echo "✓ Encrypted to $(PRIVATE_CONFIG_AGE)"; \
	else \
		echo "ERROR: $(PRIVATE_CONFIG) not found"; \
		echo "Run 'make init' to create private/ from the example"; \
		exit 1; \
	fi

# Show diff between encrypted version and current edits
diff-config:
	@if [ ! -f $(PRIVATE_CONFIG) ]; then \
		echo "ERROR: $(PRIVATE_CONFIG) not found"; \
		exit 1; \
	fi; \
	if [ ! -f $(PRIVATE_CONFIG_AGE) ]; then \
		echo "No $(PRIVATE_CONFIG_AGE) - showing entire file as new"; \
		cat $(PRIVATE_CONFIG); \
		exit 0; \
	fi; \
	age -d -i $(AGE_KEY) $(PRIVATE_CONFIG_AGE) 2>/dev/null | diff -u --color=auto - $(PRIVATE_CONFIG) || true

# Verify private/config.nix.age matches private/config.nix (for pre-commit hook)
verify:
	@if [ ! -f $(PRIVATE_CONFIG_AGE) ]; then \
		echo "⚠ No $(PRIVATE_CONFIG_AGE) - skipping verification"; \
		exit 0; \
	fi; \
	if [ ! -f $(PRIVATE_CONFIG) ]; then \
		echo "⚠ No $(PRIVATE_CONFIG) - skipping verification"; \
		exit 0; \
	fi; \
	if ! age -d -i $(AGE_KEY) $(PRIVATE_CONFIG_AGE) > .private.config.verify.tmp 2>/dev/null; then \
		rm -f .private.config.verify.tmp; \
		echo "⚠ Cannot decrypt $(PRIVATE_CONFIG_AGE) (missing key?) - skipping verification"; \
		exit 0; \
	fi; \
	if diff -q $(PRIVATE_CONFIG) .private.config.verify.tmp > /dev/null 2>&1; then \
		rm .private.config.verify.tmp; \
		echo "✓ $(PRIVATE_CONFIG_AGE) is up to date"; \
	else \
		rm -f .private.config.verify.tmp; \
		echo "✗ $(PRIVATE_CONFIG_AGE) is STALE - run 'make encrypt' before committing"; \
		exit 1; \
	fi

# Build the system using private/ flake input override
build: decrypt
	nixos-rebuild build --flake .#router --override-input private path:./$(PRIVATE_DIR)

# Switch to the new configuration using private/ flake input override
switch: decrypt
	nixos-rebuild switch --flake .#router --override-input private path:./$(PRIVATE_DIR)

# Test the new configuration (activates without adding to bootloader)
test: decrypt
	nixos-rebuild test --flake .#router --override-input private path:./$(PRIVATE_DIR)

# Run all flake checks
check:
	nix flake check

# Run flake checks with verbose output (shows build logs even if cached)
check-verbose:
	@nix flake check
	@echo ""
	@echo "=== Test Logs ==="
	@for check in lib-tests shell-tests firewall-tests dns-dhcp-tests; do \
		echo ""; \
		echo "--- $$check ---"; \
		nix log .#checks.x86_64-linux.$$check 2>/dev/null || echo "(no log available)"; \
	done

# Run pre-commit hooks on all files
lint:
	uvx pre-commit run --all-files

# Clean up decrypted file and temp files
clean:
	rm -f $(PRIVATE_CONFIG) .private.config.verify.tmp
	@echo "✓ Cleaned up $(PRIVATE_CONFIG)"
