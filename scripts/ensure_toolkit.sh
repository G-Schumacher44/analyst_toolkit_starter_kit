#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

if [ -f deploy_toolkit/Makefile ]; then
  echo "deploy_toolkit present. Nothing to do."
  exit 0
fi

if [ -f deploy_toolkit.zip ]; then
  echo "Found deploy_toolkit.zip. Unzipping at repo root..."
  unzip -o deploy_toolkit.zip >/dev/null
  if [ -f deploy_toolkit/Makefile ]; then
    echo "Unzip complete. Toolkit ready."
    exit 0
  fi
  echo "Unzip finished but expected files are still missing." >&2
fi

cat <<'EOF'
Deploy toolkit not found.

Expected:
  - deploy_toolkit/Makefile

Fix options:
  1) If you have deploy_toolkit.zip at repo root, place it here and run:
       make ensure-toolkit
  2) Copy the entire deploy_toolkit/ folder from the Starter Kit repo into this repo
  3) Download the latest bundle and unzip at repo root:
       https://github.com/G-Schumacher44/analyst_toolkit_starter_kit/releases/latest/download/deploy_toolkit.zip

Then run:
  make -f deploy_toolkit/Makefile project PROJECT_NAME=my_project DATASET=auto
EOF

exit 1
