.PHONY: help ensure-toolkit init

# Root delegator Makefile with friendly fallbacks.
# Delegates to deploy_toolkit/Makefile, or prints guidance if missing.

.DEFAULT_GOAL := help

MASTER := deploy_toolkit/Makefile

# Generic delegator with fallback message
%:
	@if [ -f "$(MASTER)" ]; then \
	  $(MAKE) -f $(MASTER) $@; \
	else \
	  echo "Missing deploy toolkit Makefile."; \
	  echo "Expected: deploy_toolkit/Makefile"; \
	  echo "Fix: unzip deploy_toolkit.zip at repo root, or run: make ensure-toolkit"; \
	  exit 1; \
	fi

help:
	@if [ -f "$(MASTER)" ]; then \
	  $(MAKE) -f $(MASTER) help; \
	else \
	  echo "Targets (once toolkit is present):"; \
	  echo "  setup, wire-data, configs, notebook, package"; \
	  echo "Toolkit missing. Fix: unzip deploy_toolkit.zip or run: make ensure-toolkit"; \
	fi

# Ensure the deploy toolkit exists by unzipping locally or guiding the user
ensure-toolkit:
	bash scripts/ensure_toolkit.sh

# Convenience: run ensure-toolkit first, then normal flow
init: ensure-toolkit
