.PHONY: help project setup setup-notebook env-conda env-venv configs wire-data notebook notebook-print smoke package clean-deploy-scaffold

# Defaults: infer ENV from folder name; KERNEL_NAME follows ENV
TARGET ?= .
ENV ?= $(notdir $(CURDIR))
KERNEL_NAME ?= Python ($(ENV))
DATASET ?= auto
GENERATE ?= 1
OFFLINE ?= 0
VSCODE_AI ?= gemini
PROJECT_NAME ?=
INGEST ?= copy

BOOTSTRAP := deploy_toolkit/scripts/bootstrap.sh

help:
	@echo "Targets:"
	@echo "  project           One-liner to scaffold + env + configs (alias of setup)"
	@echo "  setup             Alias for setup-notebook"
	@echo "  setup-notebook    Scaffold into TARGET, set dataset, create env, register kernel, copy notebook"
	@echo "  env-conda         Create Conda env and register kernel"
	@echo "  env-venv          Create venv and register kernel"
	@echo "  wire-data         Only set pipeline_entry_path in run config (DATASET=auto|prompt|/path.csv)"
	@echo "  configs           Generate inferred configs under config/generated/"
	@echo "  notebook          Open the starter notebook with Jupyter Lab"
	@echo "  notebook-print    Print a command to open the starter notebook"
	@echo "  smoke             Print a command to run a smoke test (Diag + soft Validation)"
	@echo "  package           Create a deployable zip (excluding data/ and exports/)"
	@echo "  clean-deploy-scaffold Remove prior scaffolds under deploy_toolkit/ (data, exports, config, notebooks, .vscode)"
	@echo "Variables: TARGET=., ENV, KERNEL_NAME, DATASET=(prompt|auto|/path.csv), INGEST=(copy|move|none), GENERATE=1, OFFLINE=1, VSCODE_AI=(gemini|codex|off), PROJECT_NAME"

project: setup-notebook

setup: setup-notebook

setup-notebook:
	bash $(BOOTSTRAP) \
	  --env conda --name "$(ENV)" \
	  --dataset "$(DATASET)" \
	  --ingest "$(INGEST)" \
	  --kernel-name "$(KERNEL_NAME)" \
	  --vscode-ai "$(VSCODE_AI)" \
	  --copy-notebook \
	  --target "$(TARGET)" \
	  $(if $(PROJECT_NAME),--project-name "$(PROJECT_NAME)",) \
	  $(if $(filter 1,$(GENERATE)),--generate-configs,) \
	  $(if $(filter 1,$(OFFLINE)),--offline,) \
	  --run-smoke

env-conda:
	bash $(BOOTSTRAP) --env conda --name "$(ENV)" --kernel-name "$(KERNEL_NAME)"

env-venv:
	bash $(BOOTSTRAP) --env venv --name "$(ENV)" --kernel-name "$(KERNEL_NAME)"

wire-data:
	conda run -n "$(ENV)" bash $(BOOTSTRAP) --env none --target "$(TARGET)" --dataset "$(DATASET)" --ingest "$(INGEST)" $(if $(PROJECT_NAME),--project-name "$(PROJECT_NAME)",)

configs:
	conda run -n "$(ENV)" python deploy_toolkit/scripts/infer_configs.py \
	  $(if $(INPUT),--input "$(INPUT)",) \
	  $(if $(OUTDIR),--outdir "$(OUTDIR)",) \
	  $(if $(SAMPLE_ROWS),--sample-rows $(SAMPLE_ROWS),) \
	  $(if $(MAX_UNIQUE),--max-unique $(MAX_UNIQUE),) \
	  $(if $(EXCLUDE_PATTERNS),--exclude-patterns "$(EXCLUDE_PATTERNS)",)

notebook:
	@echo "Opening Jupyter Lab with the starter notebook..."
	@conda run -n "$(ENV)" jupyter lab notebooks/toolkit_template.ipynb || (echo "If this fails, ensure Jupyter is installed in env '$(ENV)'" && exit 1)

notebook-print:
	@echo "Open the starter notebook with your selected kernel:"
	@echo "  jupyter lab notebooks/toolkit_template.ipynb"

smoke:
	bash $(BOOTSTRAP) --run-smoke --non-interactive --target "$(TARGET)"

package:
	@echo "Creating deployment zip (cross-platform; excludes data/, exports/, venv, git, __pycache__)"
	@python -c "import sys" >/dev/null 2>&1 && \
		python deploy_toolkit/scripts/package_bundle.py || \
		(py -3 -c "import sys" >/dev/null 2>&1 && py -3 deploy_toolkit/scripts/package_bundle.py) || \
		( echo "Python not found. Install Python 3 or run: py -3 deploy_toolkit/scripts/package_bundle.py" && exit 1 )
	@echo "Created deploy_bundle.zip"

clean-deploy-scaffold:
	@echo "Removing previously scaffolded folders under deploy_toolkit/ (if present)"
	@rm -rf deploy_toolkit/data deploy_toolkit/exports deploy_toolkit/notebooks deploy_toolkit/config deploy_toolkit/.vscode || true
	@echo "Done"
