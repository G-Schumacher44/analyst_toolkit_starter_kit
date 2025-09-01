#!/usr/bin/env python3
"""
Cross-platform packager for the deployment bundle.

Creates deploy_bundle.zip at the repository root containing ONLY the
`deploy_toolkit/` folder (as the top-level directory in the zip). Excludes
generated/scaffolded content inside `deploy_toolkit/` such as data/, exports/,
notebooks/, config/, .vscode/, and __pycache__. Works on Windows, macOS, and
Linux without requiring an external `zip` binary.
"""

import os
import sys
import fnmatch
import zipfile
from pathlib import Path

ROOT = Path.cwd()
BUNDLE_ROOT = ROOT / "deploy_toolkit"
OUT = ROOT / "deploy_bundle.zip"

# Exclusion globs (posix, relative to the deploy_toolkit/ folder)
EXCLUDE = [
    "data/**",
    "exports/**",
    "notebooks/**",
    "config/**",
    ".vscode/**",
    "**/__pycache__/**",
    "**/.DS_Store",
    ".DS_Store",
]

def is_excluded(rel_posix: str) -> bool:
    return any(fnmatch.fnmatch(rel_posix, pat) for pat in EXCLUDE)

def main() -> int:
    # Validate bundle root
    if not BUNDLE_ROOT.exists() or not BUNDLE_ROOT.is_dir():
        print("Error: deploy_toolkit/ folder not found at repo root.", file=sys.stderr)
        return 2

    # Ensure we do not include a stale output
    if OUT.exists():
        OUT.unlink()

    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for dirpath, dirnames, filenames in os.walk(BUNDLE_ROOT):
            # Path relative to the bundle root
            rel_dir = Path(dirpath).relative_to(BUNDLE_ROOT)
            rel_dir_posix = rel_dir.as_posix() if rel_dir != Path('.') else ''

            # Prune excluded directories for efficiency
            for d in list(dirnames):
                rel_sub = (rel_dir / d).as_posix()
                if is_excluded(rel_sub + "/") or is_excluded(rel_sub + "/**"):
                    dirnames.remove(d)

            # Process files
            for f in filenames:
                rel_file = (rel_dir / f).as_posix() if rel_dir_posix else f
                if is_excluded(rel_file):
                    continue
                abs_path = Path(dirpath) / f
                # Store under top-level deploy_toolkit/ inside the zip
                arcname = Path("deploy_toolkit") / rel_file
                zf.write(abs_path, arcname.as_posix())

    print(f"Wrote {OUT}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
