<p align="center">
  <img src="../repo_files/dark_logo_banner.png" width="1000"/>
  <br>
  <em>Analyst Toolkit — Deployment Guide</em>
</p>

# 🚀 Deployment Guide (Notebook‑First)

This guide shows how to unzip the deployment bundle, scaffold a project, auto‑ingest a dataset, infer starter configs locally (no AI, no network), and launch the notebook for Diagnostics and Validation.

---

## ✅ Prerequisites

- Conda installed and initialized in your shell (`conda --version`)
- Make available (`make --version`)
- Network access if you’re not using offline installs

Windows
- Best experience: WSL (Ubuntu). Run all commands inside WSL.
- Native Windows: use Git Bash + Make + Python 3/Conda on PATH. If `make` is missing, either use the provided `setup.cmd` from CMD/PowerShell, install Make, or call the master makefile explicitly:
  - `make -f deploy_toolkit/Makefile_master setup PROJECT_NAME=<name>`
  - Or run the bootstrapper directly with Bash:
    `bash deploy_toolkit/scripts/bootstrap.sh --env conda --name analyst-toolkit --copy-notebook --generate-configs --run-smoke`

---

## 🧩 What the Bundle Contains

- `Makefile` (at repo root): convenient targets for setup, wiring data, config inference, packaging
- `deploy_toolkit/templates/**`: configuration, env, VS Code, and notebook templates
- `deploy_toolkit/scripts/bootstrap.sh`: notebook‑first bootstrapper
- `deploy_toolkit/tool_kit_resources/**`: docs (this guide, usage, config)

---

## ⚡ Quick Start

1) Unzip the bundle at your project root (Makefile should be at `./Makefile`).
2) Add your CSV at repo root (e.g., `./my_data.csv`) or `./data/raw/`.
3) Activate Conda base:

```bash
conda activate base
```

4) Run setup (builds env, scaffolds repo, infers configs, wires dataset):

```bash
make setup PROJECT_NAME=<your_project_name>
```

Sample initial setup commands:

```bash
# Most common (auto-discovers a single CSV at root or data/raw and copies it into data/raw)
make setup PROJECT_NAME=my_project DATASET=auto

# Prompt to select when multiple CSVs are present
make setup PROJECT_NAME=my_project DATASET=prompt

# Explicit env/kernel names (optional override)
make setup ENV=deploy_toolkit KERNEL_NAME="Python (deploy_toolkit)" PROJECT_NAME=my_project DATASET=auto
```

Defaults in setup:
- `TARGET=.` (repo root)
- `ENV=<folder_name>`; `KERNEL_NAME="Python (<ENV>)"`
- `DATASET=auto` (uses single CSV; prompts if multiple)
- `INGEST=copy` (copies a root CSV into `data/raw/`)
- `GENERATE=1` (writes `config/generated/*`)

5) Launch the starter notebook:

```bash
conda activate <ENV>
make notebook
```

Then select kernel “Python (<ENV>)” and Run All.

---

Note: If your project does not have a root `Makefile`, you can always invoke the master file directly:

```bash
make -f deploy_toolkit/Makefile_master setup PROJECT_NAME=<your_project_name>
```

---

## 🔩 What Setup Produces

- Scaffolds: `config/`, `data/{raw,processed,features}`, `exports/{joblib,plots,reports}`, `notebooks/`, `.vscode/`
- Copies: `.env`, `.gitignore`, `environment.yml`, `requirements.txt`, `README.md`
- Notebook: `notebooks/toolkit_template.ipynb` (titled with `PROJECT_NAME`)
- Wiring: `config/run_toolkit_config.yaml:pipeline_entry_path` set to your CSV
- Inference (local, privacy‑safe): `config/generated/*` (validation, certification, outliers)
- Env + kernel: Conda env `<ENV>`, kernel “Python (<ENV>)”

---

## 🗂️ Data Ingestion Behavior

- If `data/raw/` contains exactly one CSV → uses that automatically
- Else, if the project root contains exactly one CSV → copies (or moves) it into `data/raw/` and wires it
- If multiple CSVs are found (root or `data/raw/`) → prompts to select (unless `DATASET=/path.csv` is provided)
- Control ingestion with `INGEST=copy|move|none` (default `copy`)

Privacy: Inference/config generation is local Python code; no AI models or network calls.

---

## 🧪 Notebook‑First Flow

1) Run M01 Diagnostics — inspect schema, nulls, cardinality, skew
2) Run M02 Validation (soft) — tune expected columns/types/ranges in YAML
3) Iterate configs, re‑run cells
4) Enable downstream modules when ready (normalization → duplicates → outliers → handling → imputation → final audit → certification strict)

---

## 🛠️ Make Targets

Common targets:

- Setup (alias for full bootstrap):
  ```bash
  make setup PROJECT_NAME=<name>
  ```

- Wire dataset later (after setup):
  ```bash
  make wire-data DATASET=auto        # auto when exactly one CSV
  make wire-data DATASET=prompt      # interactive selection
  make wire-data DATASET=/full/path.csv
  ```

- Regenerate config suggestions (local):
  ```bash
  make configs INPUT=data/raw/your.csv MAX_UNIQUE=30 SAMPLE_ROWS=50000
  ```

- Launch notebook:
  ```bash
  conda activate <ENV>
  make notebook
  ```

- Package deployable zip:
  ```bash
  make package
  ```

- Clean any prior scaffolds inside `deploy_toolkit/` (keeps templates/scripts/resources):
  ```bash
  make clean-deploy-scaffold
  ```

---

## ⚙️ Variables

These can be supplied to any `make` command:

- `TARGET`: project root (default `.`)
- `ENV`: Conda environment (default = folder name)
- `KERNEL_NAME`: Jupyter kernel (default `Python (<ENV>)`)
- `DATASET`: `auto|prompt|/path.csv` (default `auto`)
- `INGEST`: `copy|move|none` (default `copy`) — how to ingest a root CSV into `data/raw/`
- `GENERATE`: `1|0` (default `1`) — write `config/generated/*`
- `OFFLINE`: `1|0` — skip network expectations
- `VSCODE_AI`: `gemini|codex|off` — inline suggestions provider in VS Code
- `PROJECT_NAME`: used in README + notebook title

---

## 🧯 Troubleshooting

- Conda not initialized: `source "$(conda info --base)/etc/profile.d/conda.sh"`
- Script not executable: `chmod +x deploy_toolkit/scripts/bootstrap.sh`
- Multiple CSVs: use `DATASET=prompt` or pass a path with `DATASET=/path/to.csv`
- Notebook won’t open via `make notebook`: ensure Jupyter is installed in `<ENV>` or run `jupyter lab notebooks/toolkit_template.ipynb`

---

## 🔒 Privacy Notes

- Config inference is fully local: no data leaves your machine
- The toolkit avoids logging raw rows; outputs are summaries, reports, and dashboards
- `.gitignore` excludes `data/**` and `exports/**` by default

---

## ℹ️ About the deploy_toolkit folder

The `deploy_toolkit/` folder is the versioned source/sample of the deployment bundle. When this bundle is unzipped at your project root, Git ignores the entire `deploy_toolkit/` folder (and zip files) by default, so you can leave it in place without cluttering your repo.
