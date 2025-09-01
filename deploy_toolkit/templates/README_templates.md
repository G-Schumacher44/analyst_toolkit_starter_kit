# Templates

Place reusable, project-ready templates here. The bootstrap prefers this folder over `resource_hub/`.

Recommended layout:

```
templates/
  config/
    run_toolkit_config.yaml
    diag_config_template.yaml
    validation_config_template.yaml
    normalization_config_template.yaml
    certification_config_template.yaml
    dups_config_template.yaml
    outlier_config_template.yaml
    handling_config_template.yaml
    imputation_config_template.yaml
    final_audit_config_template.yaml
  notebooks/   (optional, if you want custom notebook starters)
  vscode/      (optional, e.g., settings.json to seed .vscode)
```

Usage:
- Add your template YAMLs under `templates/config/`
- Run `make scaffold` (or `bash scripts/bootstrap.sh --scaffold-only`) to copy into `config/`
- Use `--force` to overwrite existing files.

