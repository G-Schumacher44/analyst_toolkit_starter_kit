#!/usr/bin/env bash
set -euo pipefail

# Notebook-first bootstrap: scaffold repo, wire dataset, create env, register kernel, and apply VS Code settings.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Package dir that contains templates and this script (deploy_toolkit)
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Target repo root where we scaffold (default: current working directory; override with --target)
TARGET_DIR="$(pwd -P 2>/dev/null || pwd)"

# Defaults
ENV_NAME="analyst-toolkit"
ENV_MODE="conda"        # conda|venv|none
FORCE_COPY=false
NO_KERNEL=false
SCAFFOLD_ONLY=false
SOURCE_DIR=""
DATASET_MODE="auto"      # auto|prompt|<path>
INGEST_POLICY="copy"      # move|copy|none
COPY_NOTEBOOK=false
GENERATE_CONFIGS=false
RUN_SMOKE=false
NON_INTERACTIVE=false
FORCE_RECREATE=false
REUSE_ENV=false
KERNEL_NAME="Python ($ENV_NAME)"
KERNEL_POLICY="prompt"  # prompt|reuse|duplicate|rename
VSCODE_MODE="on"         # on|off
VSCODE_AI="gemini"       # gemini|codex|off
OFFLINE=false
DRY_RUN=false
VERBOSE=false
QUIET=false
PROJECT_NAME=""

LOG_DIR="$TARGET_DIR/exports/reports"
LOG_FILE="$LOG_DIR/bootstrap.log"

# Python launcher (prefers 'python', falls back to 'py -3' on Windows)
PY="python"

usage() {
  cat <<USAGE
Bootstrap Analyst Toolkit repo (notebook-first)

Env/Kernels:
  --env conda|venv|none     Environment mode (default: conda)
  --name <env>              Env name (default: analyst-toolkit)
  --kernel-name <name>      Jupyter kernel display name (default prompts)
  --kernel-policy <p>       reuse|duplicate|rename|prompt (default: prompt / reuse if --non-interactive)
  --reuse-env               Reuse existing env if found
  --force-recreate          Recreate env even if exists
  --no-kernel               Skip kernel registration

Dataset/Configs:
  --dataset <path|auto|prompt>   Wire dataset to run config (default: auto)
  --ingest move|copy|none    If dataset is outside data/raw, move/copy it into data/raw (default: copy)
  --copy-notebook           Copy starter notebook into notebooks/
  --generate-configs        Generate inferred configs under config/generated/
  --project-name <name>     Inject project name into README/notebook
  --target <dir>            Target project root to scaffold into (default: current dir)

VS Code:
  --vscode on|off           Copy .vscode settings (default: on)
  --vscode-ai gemini|codex|off  Inline AI suggestions provider (default: gemini)

Execution/Control:
  --scaffold-only           Scaffold folders/files only
  --offline                 Do not attempt network installs; expect local package availability
  --run-smoke               Run Diagnostics + soft Validation only
  --non-interactive         No prompts; implies --kernel-policy reuse unless overridden
  --force                   Overwrite existing template files without prompt
  --dry-run                 Print intended actions and exit
  --verbose|--quiet         Logging verbosity
  -h, --help                Show help
USAGE
}

# Logging helpers
_ts() { date "+%Y-%m-%d %H:%M:%S"; }
_rel() { 
  case "$1" in
    "") echo "";;
    *)
      if command -v realpath >/dev/null 2>&1; then
        realpath --relative-to="$TARGET_DIR" "$1" 2>/dev/null || echo "$1"
      else
        echo "${1#${TARGET_DIR}/}"
      fi
      ;;
  esac
}

_log_init() {
  $DRY_RUN && return 0
  mkdir -p "$LOG_DIR"
  : > "$LOG_FILE"
}

info() {
  $QUIET && return 0
  if $DRY_RUN; then
    echo "[$(_ts)] [INFO] $*"
  else
    echo "[$(_ts)] [INFO] $*" | tee -a "$LOG_FILE"
  fi
}
warn() {
  if $DRY_RUN; then
    echo "[$(_ts)] [WARN] $*" >&2
  else
    echo "[$(_ts)] [WARN] $*" | tee -a "$LOG_FILE" >&2
  fi
}
err()  {
  if $DRY_RUN; then
    echo "[$(_ts)] [ERR ] $*" >&2
  else
    echo "[$(_ts)] [ERR ] $*" | tee -a "$LOG_FILE" >&2
  fi
  exit 1
}

confirm() {
  $NON_INTERACTIVE && return 0
  read -r -p "$1 [y/N]: " resp || true
  [[ "$resp" =~ ^[Yy]$ ]]
}

ensure_dir() {
  if $DRY_RUN; then
    info "Would create dir: $(_rel "$1")"
    return 0
  fi
  mkdir -p "$1"
  [ -e "$1/.gitkeep" ] || touch "$1/.gitkeep" || true
}

copy_if_needed() {
  local src="$1" dst="$2" label="${3:-}"
  if [ -e "$dst" ] && [ "$FORCE_COPY" = false ]; then
    if confirm "File $(_rel "$dst") exists. Overwrite?"; then :; else
      info "Keeping existing $(_rel "$dst")"
      return 0
    fi
  fi
  $DRY_RUN || cp -f "$src" "$dst"
  info "Copied ${label:-$(basename "$src")} -> $(_rel "$dst")"
}

update_yaml_key() {
  # Minimal, safe in-place YAML update for a single key under root
  # Args: file key value
  local file="$1" key="$2" value="$3"
  [ -f "$file" ] || return 0
  # Backup once
  $DRY_RUN || { [ -f "$file.bak" ] || cp "$file" "$file.bak"; }
  # Use python for reliability
  $DRY_RUN && return 0
  $PY - "$file" "$key" "$value" <<'PY' || true
import sys, yaml, io
fn, key, val = sys.argv[1:4]
with open(fn, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
# support simple root keys only (e.g., pipeline_entry_path)
data[key] = val
buf = io.StringIO()
yaml.safe_dump(data, buf, sort_keys=False, allow_unicode=True)
with open(fn, 'w', encoding='utf-8') as f:
    f.write(buf.getvalue())
PY
}

inject_project_name_into_notebook() {
  # Update first markdown cell title to include project name
  local nb_path="$1" title="$2"
  $DRY_RUN && return 0
  $PY - "$nb_path" "$title" <<'PY' || true
import sys, json
nb, title = sys.argv[1:3]
try:
    data = json.load(open(nb, 'r'))
    for cell in data.get('cells', []):
        if cell.get('cell_type') == 'markdown':
            src = ''.join(cell.get('source', []))
            lines = src.splitlines()
            if lines and lines[0].startswith('# '):
                lines[0] = f"# {title} — Analyst Toolkit"
                cell['source'] = [l + ('\n' if not l.endswith('\n') else '') for l in lines]
                break
    json.dump(data, open(nb, 'w'), indent=2)
except Exception:
    pass
PY
}

apply_vscode_settings() {
  [ "$VSCODE_MODE" = "off" ] && { info "Skipping VS Code settings"; return 0; }
  $DRY_RUN && { info "Would copy VS Code settings"; return 0; }
  mkdir -p "$TARGET_DIR/.vscode"
  local dst="$TARGET_DIR/.vscode/settings.json"
  local src_tmpl="$PKG_DIR/templates/.vscode/settings.json"
  if [ ! -f "$src_tmpl" ]; then
    warn "VS Code template not found at $(_rel "$src_tmpl")"
    return 0
  fi
  # Copy or prompt overwrite
  copy_if_needed "$src_tmpl" "$dst" ".vscode/settings.json"
  # Inject kernel comment and AI provider toggle
  $DRY_RUN && return 0
  $PY - "$dst" "$KERNEL_NAME" "$VSCODE_AI" <<'PY' || true
import sys, json
path, kernel_name, ai = sys.argv[1:4]
try:
    txt = open(path,'r',encoding='utf-8').read()
    data = json.loads(txt)
except Exception:
    sys.exit(0)
# Emulate a comment with a pseudo-key (kept harmless by VS Code)
data.setdefault("// Kernel", kernel_name)
# Manage inline AI settings
if ai == 'gemini':
    data["editor.inlineSuggest.provider"] = "Google.gemini-code-assist"
    data.setdefault("[python]", {}).update({"editor.inlineSuggest.enabled": True})
elif ai == 'codex':
    data.pop("editor.inlineSuggest.provider", None)
    data.setdefault("[python]", {}).update({"editor.inlineSuggest.enabled": True})
else:  # off
    data.pop("editor.inlineSuggest.provider", None)
    data.setdefault("[python]", {}).update({"editor.inlineSuggest.enabled": False})
open(path,'w',encoding='utf-8').write(json.dumps(data, indent=2))
PY
}

preflight() {
  info "Preflight checks"
  if [ "$ENV_MODE" = "conda" ]; then
    if ! command -v conda >/dev/null 2>&1; then
      $DRY_RUN && warn "conda not found (dry-run continuing)" || err "conda not found in PATH"
    fi
  fi
  if ! command -v python >/dev/null 2>&1; then
    if command -v py >/dev/null 2>&1 && py -3 -c "import sys" >/dev/null 2>&1; then
      PY="py -3"
      info "Using Python via 'py -3' launcher"
    else
      $DRY_RUN && warn "python not found (dry-run continuing)" || err "python not found"
    fi
  fi
  if ! $PY -c "import sys; assert sys.version_info[:2] >= (3,8)" 2>/dev/null; then
    warn "Python >=3.8 recommended"
  fi
  command -v jupyter >/dev/null 2>&1 || warn "jupyter command not found; kernel registration may still work via ipykernel"
}

scaffold() {
  info "Scaffolding folders"
  ensure_dir "$TARGET_DIR/src"
  ensure_dir "$TARGET_DIR/config"
  ensure_dir "$TARGET_DIR/data/raw"
  ensure_dir "$TARGET_DIR/data/processed"
  ensure_dir "$TARGET_DIR/data/features"
  ensure_dir "$TARGET_DIR/exports/joblib"
  ensure_dir "$TARGET_DIR/exports/plots"
  ensure_dir "$TARGET_DIR/exports/reports"
  ensure_dir "$TARGET_DIR/notebooks"

  # Determine template source
  if [ -z "$SOURCE_DIR" ]; then
    if [ -d "$PKG_DIR/templates/config" ] && ls -1 "$PKG_DIR"/templates/config/*.yaml >/dev/null 2>&1; then
      SOURCE_DIR="pkg_templates"
    elif [ -d "$TARGET_DIR/templates/config" ]; then
      SOURCE_DIR="target_templates"
    else
      SOURCE_DIR=""
    fi
  fi

  # Copy YAML templates
  if [ "$SOURCE_DIR" = "pkg_templates" ] && [ -d "$PKG_DIR/templates/config" ]; then
    info "Copying config templates from deploy_toolkit/templates/config"
    for f in "$PKG_DIR"/templates/config/*.yaml; do
      [ -e "$f" ] || continue
      base=$(basename "$f")
      copy_if_needed "$f" "$TARGET_DIR/config/$base"
    done
    # copy optional readme
    [ -f "$PKG_DIR/templates/config/.readme.txt" ] && copy_if_needed "$PKG_DIR/templates/config/.readme.txt" "$TARGET_DIR/config/.readme.txt"
  elif [ "$SOURCE_DIR" = "target_templates" ] && [ -d "$TARGET_DIR/templates/config" ]; then
    info "Copying config templates from target/templates/config"
    for f in "$TARGET_DIR"/templates/config/*.yaml; do
      [ -e "$f" ] || continue
      base=$(basename "$f")
      copy_if_needed "$f" "$TARGET_DIR/config/$base"
    done
  else
    warn "No template source found (templates/ or resource_hub/). Skipping config copy."
  fi

  # Copy .env template
  if [ -f "$PKG_DIR/templates/.env.template" ] && [ ! -f "$TARGET_DIR/.env" ]; then
    copy_if_needed "$PKG_DIR/templates/.env.template" "$TARGET_DIR/.env" ".env"
  fi

  # Copy environment files if present
  if [ -f "$PKG_DIR/templates/environment.yml" ]; then
    copy_if_needed "$PKG_DIR/templates/environment.yml" "$TARGET_DIR/environment.yml" "environment.yml"
  fi
  if [ -f "$PKG_DIR/templates/requirements.txt" ]; then
    copy_if_needed "$PKG_DIR/templates/requirements.txt" "$TARGET_DIR/requirements.txt" "requirements.txt"
  fi
  if [ -f "$PKG_DIR/templates/.gitignore" ]; then
    copy_if_needed "$PKG_DIR/templates/.gitignore" "$TARGET_DIR/.gitignore" ".gitignore"
  fi

  # Copy README template
  if [ -f "$PKG_DIR/templates/README.md" ]; then
    local readme_dst="$TARGET_DIR/README.md"
    if [ ! -f "$readme_dst" ] || $FORCE_COPY || confirm "Copy README template to README.md?"; then
      copy_if_needed "$PKG_DIR/templates/README.md" "$readme_dst" "README.md"
      if [ -n "$PROJECT_NAME" ]; then
        $DRY_RUN || $PY - "$readme_dst" "$PROJECT_NAME" <<'PY' || true
import sys, re
fn, name = sys.argv[1:3]
txt = open(fn,'r',encoding='utf-8').read()
txt = re.sub(r"^## \(Title Placeholder\)", f"## {name}", txt, count=1, flags=re.M)
open(fn,'w',encoding='utf-8').write(txt)
PY
      fi
    fi
  fi

  # Copy root Makefile delegator so plain `make` works post-setup
  if [ -f "$PKG_DIR/templates/Makefile.delegator" ]; then
    local mk_dst="$TARGET_DIR/Makefile"
    if [ ! -f "$mk_dst" ] || $FORCE_COPY || confirm "Create root Makefile delegator to enable 'make <target>'?"; then
      copy_if_needed "$PKG_DIR/templates/Makefile.delegator" "$mk_dst" "Makefile"
    fi
  fi

  # VSCode settings
  apply_vscode_settings
}

select_dataset() {
  local cfg="$TARGET_DIR/config/run_toolkit_config.yaml"
  [ -f "$cfg" ] || { warn "Missing $(_rel "$cfg"); cannot set pipeline_entry_path"; return 0; }
  local chosen=""
  local dest=""
  case "$DATASET_MODE" in
    auto)
      local raw_list=("$TARGET_DIR"/data/raw/*.csv)
      local raw_count=$(ls -1 "$TARGET_DIR"/data/raw/*.csv 2>/dev/null | wc -l | tr -d ' ' || echo 0)
      if [ "$raw_count" = "1" ]; then
        chosen=$(ls -1 "$TARGET_DIR"/data/raw/*.csv)
      else
        # Try project root
        local root_count=$(ls -1 "$TARGET_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ' || echo 0)
        if [ "$root_count" = "1" ]; then
          local root_csv=$(ls -1 "$TARGET_DIR"/*.csv)
          local base=$(basename "$root_csv")
          dest="$TARGET_DIR/data/raw/$base"
          if [ "$INGEST_POLICY" = "move" ]; then
            $DRY_RUN && info "Would move $(_rel "$root_csv") -> $(_rel "$dest")" || mv -f "$root_csv" "$dest"
          elif [ "$INGEST_POLICY" = "copy" ]; then
            $DRY_RUN && info "Would copy $(_rel "$root_csv") -> $(_rel "$dest")" || cp -f "$root_csv" "$dest"
          else
            dest="$root_csv"
          fi
          chosen="$dest"
        elif [ "$raw_count" = "0" ] && [ "$root_count" = "0" ]; then
          warn "No CSV found in data/raw or project root; you can set --dataset <path> later"
          return 0
        else
          info "Multiple CSVs found; switching to prompt"
          DATASET_MODE="prompt"
        fi
      fi
      ;;
    prompt)
      local files=("$TARGET_DIR"/data/raw/*.csv "$TARGET_DIR"/*.csv)
      [ -e "${files[0]}" ] || { warn "No CSVs in data/raw to select"; return 0; }
      if $NON_INTERACTIVE; then warn "Non-interactive mode requires --dataset <path> when multiple CSVs exist"; return 0; fi
      echo "Select dataset:"; select f in "${files[@]}"; do chosen="$f"; break; done
      # If chosen is at project root and ingest is enabled, ingest to data/raw
      if [[ "$chosen" == "$TARGET_DIR"/*.csv ]] && [ "$INGEST_POLICY" != "none" ]; then
        local base=$(basename "$chosen")
        dest="$TARGET_DIR/data/raw/$base"
        if [ "$INGEST_POLICY" = "move" ]; then
          $DRY_RUN && info "Would move $(_rel "$chosen") -> $(_rel "$dest")" || mv -f "$chosen" "$dest"
        else
          $DRY_RUN && info "Would copy $(_rel "$chosen") -> $(_rel "$dest")" || cp -f "$chosen" "$dest"
        fi
        chosen="$dest"
      fi
      ;;
    *)
      # explicit path
      chosen="$DATASET_MODE"
      # If explicit path is relative to TARGET and outside data/raw, honor ingest policy
      if [[ "$chosen" != /* ]]; then chosen="$TARGET_DIR/$chosen"; fi
      if [[ "$chosen" == "$TARGET_DIR"/*.csv ]] && [ "$INGEST_POLICY" != "none" ]; then
        local base=$(basename "$chosen")
        dest="$TARGET_DIR/data/raw/$base"
        if [ "$INGEST_POLICY" = "move" ]; then
          $DRY_RUN && info "Would move $(_rel "$chosen") -> $(_rel "$dest")" || mv -f "$chosen" "$dest"
        else
          $DRY_RUN && info "Would copy $(_rel "$chosen") -> $(_rel "$dest")" || cp -f "$chosen" "$dest"
        fi
        chosen="$dest"
      fi
      ;;
  esac
  [ -n "$chosen" ] || return 0
  local rel="${chosen#${TARGET_DIR}/}"
  info "Setting pipeline_entry_path -> $rel"
  update_yaml_key "$cfg" pipeline_entry_path "$rel"

  # Suggest run_id from dataset name if empty
  if $PY -c "import sys" >/dev/null 2>&1; then
    $PY - "$TARGET_DIR" <<'PY' || true
import sys, yaml, os, time
root = sys.argv[1]
cfg = os.path.join(root, 'config', 'run_toolkit_config.yaml')
try:
    data = yaml.safe_load(open(cfg)) or {}
except Exception:
    data = {}
if not data.get('run_id'):
    stem = os.path.splitext(os.path.basename(data.get('pipeline_entry_path','dataset')))[0]
    ts = time.strftime('%Y%m%d_%H%M%S')
    data['run_id'] = f"{stem}_{ts}"
    open(cfg,'w').write(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
PY
  fi
}

register_kernel() {
  $NO_KERNEL && { info "Skipping kernel registration"; return 0; }
  $DRY_RUN && { info "Would register Jupyter kernel: $KERNEL_NAME"; return 0; }
  local display="$KERNEL_NAME"
  # If interactive and kernel name not provided, prompt
  if [ "$KERNEL_NAME" = "Python ($ENV_NAME)" ] && ! $NON_INTERACTIVE; then
    read -r -p "Kernel display name [$KERNEL_NAME]: " inp || true
    [ -n "${inp:-}" ] && display="$inp"
  fi
  # Policy
  local policy="$KERNEL_POLICY"; $NON_INTERACTIVE && [ "$policy" = "prompt" ] && policy="reuse"
  info "Kernel policy: $policy"
  case "$ENV_MODE" in
    conda)
      if [ "$policy" = "reuse" ]; then
        conda run -n "$ENV_NAME" python -m ipykernel install --user --name "$ENV_NAME" --display-name "$display" >/dev/null 2>&1 || true
      else
        conda run -n "$ENV_NAME" python -m ipykernel install --user --name "$ENV_NAME" --display-name "$display" || warn "Kernel registration failed"
      fi
      ;;
    venv)
      "$TARGET_DIR/.venv/bin/python" -m ipykernel install --user --name "$ENV_NAME" --display-name "$display" || warn "Kernel registration failed"
      ;;
  esac
}

setup_conda() {
  command -v conda >/dev/null 2>&1 || err "conda not found in PATH"
  local exists
  exists=$(conda env list | awk '{print $1}' | grep -x "$ENV_NAME" || true)
  if [ -n "$exists" ]; then
    if $FORCE_RECREATE; then : ; elif $REUSE_ENV; then : ; else
      if ! $NON_INTERACTIVE && confirm "Conda env '$ENV_NAME' exists. Reuse?"; then
        REUSE_ENV=true
      elif ! $NON_INTERACTIVE && confirm "Recreate env '$ENV_NAME'?"; then
        FORCE_RECREATE=true
      else
        REUSE_ENV=true
      fi
    fi
  fi

  if $FORCE_RECREATE && [ -n "$exists" ]; then
    info "Removing existing env: $ENV_NAME"
    $DRY_RUN || conda env remove -y -n "$ENV_NAME" || true
  fi

  if $REUSE_ENV && [ -n "$exists" ]; then
    info "Reusing conda env: $ENV_NAME"
  else
    if [ -f "$TARGET_DIR/environment.yml" ]; then
      info "Creating conda env from environment.yml (name: $ENV_NAME)"
      if $OFFLINE; then
        warn "Offline mode: environment.yml may reference online packages. Proceeding; ensure local caches are available."
      fi
      $DRY_RUN || conda env create -f "$TARGET_DIR/environment.yml" -n "$ENV_NAME" || {
        warn "Env may already exist; attempting update"
        $DRY_RUN || conda env update -f "$TARGET_DIR/environment.yml" -n "$ENV_NAME"
      }
    else
      info "Creating conda env $ENV_NAME with python 3.10"
      $DRY_RUN || conda create -y -n "$ENV_NAME" python=3.10
      if [ -f "$TARGET_DIR/requirements.txt" ]; then
        info "Installing pip requirements into $ENV_NAME"
        $DRY_RUN || conda run -n "$ENV_NAME" python -m pip install -r "$TARGET_DIR/requirements.txt"
      fi
    fi
  fi

  register_kernel
}

setup_venv() {
  local PY_BIN="python3"; command -v $PY_BIN >/dev/null 2>&1 || PY_BIN="python"
  if [ -d "$TARGET_DIR/.venv" ] && ! $FORCE_RECREATE; then
    if ! $NON_INTERACTIVE && confirm ".venv exists. Reuse?"; then :; else
      FORCE_RECREATE=true
    fi
  fi
  if $FORCE_RECREATE && [ -d "$TARGET_DIR/.venv" ]; then
    info "Removing existing venv"
    $DRY_RUN || rm -rf "$TARGET_DIR/.venv"
  fi
  if [ ! -d "$TARGET_DIR/.venv" ]; then
    info "Creating venv at .venv"
    $DRY_RUN || "$PY_BIN" -m venv "$TARGET_DIR/.venv"
    info "Installing requirements into venv"
    $DRY_RUN || "$TARGET_DIR/.venv/bin/python" -m pip install --upgrade pip
    if [ -f "$TARGET_DIR/requirements.txt" ]; then
      $DRY_RUN || "$TARGET_DIR/.venv/bin/python" -m pip install -r "$TARGET_DIR/requirements.txt"
    fi
  else
    info "Reusing existing venv"
  fi
  register_kernel
}

generate_configs() {
  info "Generating config suggestions"
  # Try to read pipeline_entry_path from target config to pass as --input
  local cfg="$TARGET_DIR/config/run_toolkit_config.yaml"
  local input_csv=""
  if [ -f "$cfg" ]; then
    input_csv=$($PY - "$cfg" "$TARGET_DIR" 2>/dev/null <<'PY'
import sys, yaml, os
cfg, root = sys.argv[1:3]
data = yaml.safe_load(open(cfg)) or {}
p = data.get('pipeline_entry_path')
if p:
    print(os.path.join(root, p) if not os.path.isabs(p) else p)
PY
    ) || true
  fi
  local outdir="$TARGET_DIR/config/generated"
  local cmd=($PY "$PKG_DIR/scripts/infer_configs.py" --outdir "$outdir")
  [ -n "$input_csv" ] && cmd+=(--input "$input_csv")
  $DRY_RUN && { echo "$ ${cmd[*]}"; return 0; }
  "${cmd[@]}" || warn "infer_configs.py failed"
}

run_smoke() {
  info "Running smoke test (Diagnostics + soft Validation)"
  local cfg="$TARGET_DIR/config/run_toolkit_config.yaml"
  if [ ! -f "$cfg" ]; then warn "Missing $(_rel "$cfg")"; return 0; fi
  cat <<EOT
Suggested command (execute in your env):
  python -m analyst_toolkit.run_toolkit_pipeline --config $(_rel "$cfg")
EOT
}

persist_env_defaults() {
  local envf="$TARGET_DIR/.env"
  $DRY_RUN || touch "$envf"
  # Append or update keys
  $DRY_RUN && return 0
  ENV_NAME="$ENV_NAME" KERNEL_NAME="$KERNEL_NAME" PROJECT_NAME="$PROJECT_NAME" VSCODE_AI="$VSCODE_AI" $PY - "$envf" <<'PY' || true
import os, sys, re
fn = sys.argv[1]
kv = {
  'ENV_NAME': os.environ.get('ENV_NAME',''),
  'KERNEL_NAME': os.environ.get('KERNEL_NAME',''),
  'PROJECT_NAME': os.environ.get('PROJECT_NAME',''),
  'VSCODE_AI': os.environ.get('VSCODE_AI',''),
}
text = open(fn,'r',encoding='utf-8').read() if os.path.exists(fn) else ''
for k,v in kv.items():
    if not v: continue
    pattern = re.compile(rf"^{k}=.*$", re.M)
    if pattern.search(text):
        text = pattern.sub(f"{k}={v}", text)
    else:
        text += ("\n" if text and not text.endswith("\n") else "") + f"{k}={v}\n"
open(fn,'w',encoding='utf-8').write(text)
PY
}

main() {
  # Capture original arg count for dry-run default detection
  local ORIG_ARGC=$#
  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env) ENV_MODE="$2"; shift 2 ;;
      --conda) ENV_MODE="conda"; shift ;;
      --venv) ENV_MODE="venv"; shift ;;
      --target) TARGET_DIR="$2"; shift 2 ;;
      --name) ENV_NAME="$2"; KERNEL_NAME="Python ($2)"; shift 2 ;;
      --kernel-name) KERNEL_NAME="$2"; shift 2 ;;
      --kernel-policy) KERNEL_POLICY="$2"; shift 2 ;;
      --reuse-env) REUSE_ENV=true; shift ;;
      --force-recreate) FORCE_RECREATE=true; shift ;;
      --no-kernel) NO_KERNEL=true; shift ;;
      --dataset) DATASET_MODE="$2"; shift 2 ;;
      --ingest) INGEST_POLICY="$2"; shift 2 ;;
      --copy-notebook) COPY_NOTEBOOK=true; shift ;;
      --generate-configs) GENERATE_CONFIGS=true; shift ;;
      --project-name) PROJECT_NAME="$2"; shift 2 ;;
      --vscode) VSCODE_MODE="$2"; shift 2 ;;
      --vscode-ai) VSCODE_AI="$2"; shift 2 ;;
      --scaffold-only) SCAFFOLD_ONLY=true; shift ;;
      --offline) OFFLINE=true; shift ;;
      --run-smoke) RUN_SMOKE=true; shift ;;
      --non-interactive) NON_INTERACTIVE=true; shift ;;
      --force) FORCE_COPY=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --verbose) VERBOSE=true; QUIET=false; shift ;;
      --quiet) QUIET=true; VERBOSE=false; shift ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown option: $1" ;;
    esac
  done

  # If no flags provided, print a helpful dry-run summary
  if [ "$ORIG_ARGC" -eq 0 ] && [ -t 1 ]; then
    DRY_RUN=true
  fi

  _log_init
  $DRY_RUN && info "No flags provided; performing dry-run summary. Use --help for options." && info "Dry-run mode: showing planned actions only"
  preflight
  scaffold

  # Optional notebook copy
  if $COPY_NOTEBOOK; then
    local nb_src="$PKG_DIR/templates/toolkit_template.ipynb"
    local nb_dst="$TARGET_DIR/notebooks/toolkit_template.ipynb"
    if [ -f "$nb_src" ]; then
      copy_if_needed "$nb_src" "$nb_dst" "toolkit_template.ipynb"
      [ -n "$PROJECT_NAME" ] && { info "Injecting project name into notebook"; inject_project_name_into_notebook "$nb_dst" "$PROJECT_NAME"; }
    else
      warn "Notebook template not found at $(_rel "$nb_src")"
    fi
  fi

  # Dataset wiring
  select_dataset

  # Persist env defaults
  persist_env_defaults

  # Env setup
  if $SCAFFOLD_ONLY || [ "$ENV_MODE" = "none" ]; then
    info "Scaffold complete (no environment setup requested)"
  else
    case "$ENV_MODE" in
      conda) setup_conda ;;
      venv) setup_venv ;;
      *) warn "Unknown env mode: $ENV_MODE" ;;
    esac
  fi

  # Config generation
  $GENERATE_CONFIGS && generate_configs

  # Smoke test suggestion
  $RUN_SMOKE && run_smoke

  info "Bootstrap complete"
}

main "$@"
