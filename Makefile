.PHONY: help

# Thin delegator Makefile at repo root.
# Forwards all targets to the master Makefile in deploy_toolkit/.

MASTER := deploy_toolkit/Makefile_master

.DEFAULT_GOAL := help

%:
	@$(MAKE) -f $(MASTER) $@

help:
	@$(MAKE) -f $(MASTER) help

