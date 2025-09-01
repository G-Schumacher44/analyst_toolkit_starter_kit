<p align="center">
  <img src="../logo_img/dark_logo_banner.png" alt="Analyst Toolkit" width="900"/>
  <br>
  <em>Analyst Toolkit — QA + Cleaning Engine</em>
</p>
</p>
<p align="center">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="Status" src="https://img.shields.io/badge/status-stable-brightgreen">
  <img alt="Version" src="https://img.shields.io/badge/version-v0.1.0-blueviolet">
</p>


# 📘 Analyst Toolkit — Usage Guide

This guide walks through how to use the Analyst Toolkit for data cleaning, validation, and QA auditing, using either individual modules or the full pipeline.


## ⚙️ Setup

For most users, install via the project’s `environment.yml` (created during setup) or use the toolkit’s `requirements.txt` under `deploy_toolkit/`.

---

## ⚙️ Configuration Files

Each module is configured via a YAML file located in the `config/` directory. These files control:

- File paths for inputs/outputs
- Behavior toggles (e.g., `run: true`, `show_inline: true`)
- Thresholds and expected schema
- Plotting and export options

> 📌 See each config template in `config/` for structure and examples.

<details>
<summary><strong>⚙️ YAML Example (Final Audit Template)</strong></summary>

**Sample Configuration (`final_audit_config_template.yaml`)**
```yaml
final_audit:
  run: true
  final_edits:
    drop_columns:
      - 'body_mass_g_zscore_outlier'
      - 'bill_length_mm_iqr_outlier'
    # You can also add rename_columns and coerce_dtypes here
  certification:
    run: true
    fail_on_error: true
    rules:
      # ... strict validation rules ...
      disallowed_null_columns:
        - 'tag_id'
        - 'species'
```

When running the full pipeline in either `notebook` or `CLI` each module reads its own YAML config file, with optional global overrides in `config/run_toolkit_config.yaml`. 

**Example:**

```YAML
final_audit:
  run: true
  input_path: "exports/joblib/{run_id}_m07_cleaned_dataset.joblib"

  checks:
    no_nulls: true
    expected_columns:
      - "tag_id"
      - "species"
      - "bill_length_mm"
      - "body_mass_g"
    range_checks:
      bill_length_mm:
        min: 25
        max: 65
      body_mass_g:
        min: 2500
        max: 6500

```
</details>

---


## 🧪 Using the Toolkit

<details>
<summary><strong>📚 Modular Notebook Use</strong></summary>
<br>


Use `notebooks/toolkit_template.ipynb` to:

- Run one module at a time
- Inspect intermediate results
- Display inline dashboards
- Tweak parameters or YAML and re-run

Each stage (M01–M10) can be executed individually with full visibility.

>See [📗 Notebook Usage Guide](./notebook_usage_guide.md) for a full breakdown

<details>
<summary><strong>Notebook Example</strong></summary>


**🔬 Modular Stage (M05: Outlier Detection)**

```python
from analyst_toolkit.m00_utils.config_loader import load_config
from analyst_toolkit.m05_detect_outliers.run_detection_pipeline import run_outlier_detection_pipeline

config = load_config("config/outlier_config_template.yaml")
outlier_cfg = config.get("outlier_detection", {})
run_id = config.get("run_id")
notebook_mode = config.get("notebook", True)

df_outliers_flagged, results = run_outlier_detection_pipeline(
    config=outlier_cfg,
    df=df_deduped,
    notebook=notebook_mode,
    run_id=run_id
)
```

</details>

---

</details>

<details>
<summary><strong>⚙️ Pipeline Execution</strong></summary>
<br>

Run the CLI directly or use your project’s notebook;

### 🔩 For pipeline use with CLI or Notebook 

**In CLI**

```bash

python -m analyst_toolkit.run_toolkit_pipeline --config config/run_toolkit_config.yaml

```

This runs all pipeline stages in order using the config file. Outputs include:

- Final certified CSV
- Joblib checkpoints
- Exported XLSX/CSV reports
- Saved plots for every module

You can also set `notebook: false` to run in silent (headless) mode for automation.

</details>

<details>
<summary><strong>📦 Programmatic Use</strong></summary>
<br>


You can also import and use modules like any Python package (the toolkit is installed by your environment):

```python
from analyst_toolkit.m02_validation.run_validation_pipeline import run_validation_pipeline
from analyst_toolkit.m00_utils.config_loader import load_config

config = load_config("config/validation_config_template.yaml")
validation_cfg = config.get("validation", {})

validated_df = run_validation_pipeline(
    config=validation_cfg,
    df=df,
    run_id="demo_run",
    notebook=True
)
```

This allows programmatic access to every pipeline module without running the full system.

</details>


## 🧭 Module Index

| Stage | Module            | Description                                          |
| ----- | ----------------- | ---------------------------------------------------- |
| M01   | Diagnostics       | Profile data: shape, types, nulls, skew, sample      |
| M02   | Validation        | Schema check, dtype verification, null rules         |
| M03   | Normalization     | Clean up whitespace, case, type coercion             |
| M04   | Duplicates        | Flag/remove exact row duplicates                     |
| M05   | Outlier Detection | Detect outliers using IQR or Z-score                 |
| M06   | Outlier Handling  | Transform, impute, or clip flagged outliers          |
| M07   | Imputation        | Fill missing values via mean, median, mode, constant |
| M08   | Visuals           | Generate profile plots, skew plots, heatmaps         |
| M10   | Final Audit       | Final cleanup, schema cert, and export               |

---

## 🛠️ YAML Tips

- Use `{run_id}` in paths for auto-named outputs
- Set `show_inline: true` for notebook dashboards
- Use `checkpoint: true` to save intermediate DataFrames
- You can safely skip modules by setting `run: false`
- Set `logging:` to control global logging behavior:
  - `on`: always log to console or file
  - `off`: disable logging entirely
  - `auto`: follow `notebook_mode` logic — quiet in notebooks, verbose in CLI

---

## 📦 Artifacts Produced

- HTML-styled dashboards (if `notebook: true`)
- Checkpointed `.joblib` files per module
- XLSX/CSV summary reports
- Boxplots, histograms, and validation plots

---

## 🔗 Quick Access

[📁 View YAML Configs ›](https://github.com/G-Schumacher44/analyst_toolkit/tree/main/config)

<div style="margin-top: 1em; margin-bottom: 1em;">
  
<a href="https://github.com/G-Schumacher44/analyst_toolkit/blob/main/notebooks/00_analyst_toolkit_modular_demo.ipynb">
  <img src="https://img.shields.io/badge/Demo_Notebook-00_Modular-blue?logo=jupyter" style="margin: 4px;" />
</a>

<a href="https://github.com/G-Schumacher44/analyst_toolkit/blob/main/notebooks/01_analyst_toolkit_pipeline_demo.ipynb">
  <img src="https://img.shields.io/badge/Demo_Notebook-01_Full_Pipeline-purple?logo=jupyter" style="margin: 4px;" />
</a>

</div>

___

## 🧠 Need Help?

This project is designed to be auditable and transparent. For help:

- View example notebooks in `/notebooks/`
- Read module docstrings for function usage
- Ask a question via GitHub Issues

---

<p align="center">
  <a href="../README.md">🏠 <b>Main README</b></a>
  &nbsp;·&nbsp;
  <a href="./deployment_guide.md">🚀 <b>Deployment</b></a>
  &nbsp;·&nbsp;
  <a href="./usage_guide.md">📘 <b>Usage</b></a>
  &nbsp;·&nbsp;
  <a href="./config_guide.md">🧭 <b>Config</b></a>
  &nbsp;·&nbsp;
  <a href="./notebook_usage_guide.md">📗 <b>Notebooks</b></a>
</p>
<p align="center">
  <sub>✨ Analyst Toolkit · Starter Kit ✨</sub>
</p>
