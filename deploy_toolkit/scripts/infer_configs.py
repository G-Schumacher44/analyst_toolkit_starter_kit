#!/usr/bin/env python3
import sys
import os
import glob
import re
import argparse
from typing import Dict, Any, List, Tuple

import pandas as pd
import yaml


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))


def load_yaml(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def write_yaml(path: str, data: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)


def find_entry_csv() -> str:
    cfg_path = os.path.join(ROOT, "config", "run_toolkit_config.yaml")
    if os.path.exists(cfg_path):
        cfg = load_yaml(cfg_path)
        p = (cfg or {}).get("pipeline_entry_path")
        if p:
            p_abs = os.path.join(ROOT, p) if not os.path.isabs(p) else p
            if os.path.exists(p_abs):
                return p_abs

    candidates = sorted(glob.glob(os.path.join(ROOT, "data", "raw", "*.csv")))
    if len(candidates) == 1:
        return candidates[0]
    raise SystemExit(
        "Could not determine entry CSV. Set --input or pipeline_entry_path in config/run_toolkit_config.yaml or place exactly one CSV in data/raw/."
    )


def infer_types(df: pd.DataFrame, detect_datetimes: bool = True) -> Dict[str, str]:
    types: Dict[str, str] = {}
    for col in df.columns:
        s = df[col]
        dtype = str(s.dtype)
        # Attempt datetime inference for object columns
        if detect_datetimes and dtype == "object":
            sample = s.dropna().astype(str).head(500)
            if not sample.empty:
                parsed = pd.to_datetime(sample, errors="coerce", infer_datetime_format=True)
                if parsed.notna().mean() >= 0.9:
                    types[col] = "datetime64[ns]"
                    continue
        types[col] = dtype
    return types


def infer_categoricals(
    df: pd.DataFrame, 
    max_unique: int = 30, 
    top_n: int = 30,
    exclude_patterns: List[re.Pattern] | None = None,
) -> Dict[str, list]:
    cats: Dict[str, list] = {}
    for col in df.columns:
        s = df[col]
        if exclude_patterns and any(p.search(col) for p in exclude_patterns):
            continue
        if s.dtype == "object" or str(s.dtype).startswith("category") or s.nunique(dropna=True) <= max_unique:
            vals = (
                s.dropna().astype(str).value_counts().index.tolist()[: top_n]
            )
            if vals:
                cats[col] = sorted(list(set(vals)))
    return cats


def infer_numeric_ranges(df: pd.DataFrame) -> Dict[str, Dict[str, float]]:
    ranges: Dict[str, Dict[str, float]] = {}
    for col in df.columns:
        s = df[col]
        if pd.api.types.is_numeric_dtype(s):
            s_clean = s.dropna()
            if s_clean.empty:
                continue
            min_v = float(s_clean.min())
            max_v = float(s_clean.max())
            ranges[col] = {"min": min_v, "max": max_v}
    return ranges


def build_validation_config(input_path_rel: str, cols, types, cats, ranges, fail_on_error: bool) -> Dict[str, Any]:
    return {
        "notebook": True,
        "run_id": "",
        "logging": "auto",
        "validation": {
            "input_path": input_path_rel,
            "schema_validation": {
                "run": True,
                "fail_on_error": bool(fail_on_error),
                "rules": {
                    "expected_columns": list(cols),
                    "expected_types": types,
                    "categorical_values": cats,
                    "numeric_ranges": ranges,
                },
            },
            "settings": {
                "checkpoint": False,
                "export": True,
                "as_csv": False,
                "export_path": "exports/reports/validation/validation_report.xlsx",
                "show_inline": True,
            },
        },
    }


def build_outlier_config(input_path_rel: str, numeric_cols) -> Dict[str, Any]:
    detection_specs = {c: {"method": "iqr", "iqr_multiplier": 1.5} for c in numeric_cols}
    detection_specs["__default__"] = {"method": "iqr", "iqr_multiplier": 2.0}
    return {
        "notebook": True,
        "run_id": "",
        "logging": "auto",
        "outlier_detection": {
            "run": True,
            "input_path": input_path_rel,
            "detection_specs": detection_specs,
            "exclude_columns": [],
            "append_flags": True,
            "plotting": {
                "run": True,
                "plot_save_dir": "exports/plots/outliers/{run_id}",
                "plot_types": ["box", "hist"],
                "show_plots_inline": True,
            },
            "export": {"run": True, "export_dir": "exports/reports/outliers/detection/", "as_csv": False},
            "checkpoint": {"run": True, "checkpoint_path": "exports/joblib/{run_id}/{run_id}_m05_outliers_flagged.joblib"},
        },
    }

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Infer Analyst Toolkit configs from a CSV")
    p.add_argument("--input", help="Path to input CSV; defaults to run config or data/raw single CSV")
    p.add_argument("--outdir", default=os.path.join(ROOT, "config", "generated"), help="Output directory for generated YAMLs")
    p.add_argument("--sample-rows", type=int, default=None, help="Sample first N rows for inference for speed")
    p.add_argument("--max-unique", type=int, default=30, help="Max unique values to consider a column categorical")
    p.add_argument("--exclude-patterns", default="id|uuid|tag", help="Regex for columns to exclude from categorical/outlier inference")
    p.add_argument("--detect-datetimes", choices=["on","off"], default="on", help="Attempt to infer datetime types from object cols")
    p.add_argument("--datetime-hints", nargs="*", default=[], help="Hints of the form col:strftime, e.g., capture_date:%Y-%m-%d")
    return p.parse_args()


def apply_datetime_hints(df: pd.DataFrame, hints: List[str]) -> Tuple[pd.DataFrame, Dict[str, str]]:
    formats: Dict[str, str] = {}
    for hint in hints:
        if ":" not in hint:
            continue
        col, fmt = hint.split(":", 1)
        col = col.strip()
        fmt = fmt.strip()
        if col in df.columns:
            try:
                df[col] = pd.to_datetime(df[col], format=fmt, errors="coerce")
                formats[col] = "datetime64[ns]"
            except Exception:
                pass
    return df, formats


def main():
    args = parse_args()
    input_csv = args.input or find_entry_csv()
    rel_path = os.path.relpath(input_csv, ROOT)
    print(f"[INFO] Inspecting: {rel_path}")

    read_kwargs = dict(low_memory=False)
    if args.sample_rows:
        read_kwargs["nrows"] = args.sample_rows
    df = pd.read_csv(input_csv, **read_kwargs)

    # Apply datetime hints first
    df, hinted_types = apply_datetime_hints(df, args.datetime_hints)

    detect_dt = args.detect_datetimes == "on"
    cols = list(df.columns)
    types = infer_types(df, detect_datetimes=detect_dt)
    types.update(hinted_types)

    exclude_re = [re.compile(args.exclude_patterns)] if args.exclude_patterns else []
    cats = infer_categoricals(df, max_unique=args.max_unique, exclude_patterns=exclude_re)
    ranges = infer_numeric_ranges(df)

    # Build suggestions
    validation = build_validation_config(rel_path, cols, types, cats, ranges, fail_on_error=False)
    certification = build_validation_config(rel_path, cols, types, cats, ranges, fail_on_error=True)
    numeric_cols = [c for c in df.columns if pd.api.types.is_numeric_dtype(df[c])]
    # Exclude numeric columns matching exclude patterns
    numeric_cols = [c for c in numeric_cols if not any(p.search(c) for p in exclude_re)]
    outliers = build_outlier_config(rel_path, numeric_cols)

    out_dir = args.outdir
    os.makedirs(out_dir, exist_ok=True)
    write_yaml(os.path.join(out_dir, "validation_config_autofill.yaml"), validation)
    write_yaml(os.path.join(out_dir, "certification_config_autofill.yaml"), certification)
    write_yaml(os.path.join(out_dir, "outlier_config_autofill.yaml"), outliers)
    print(f"[INFO] Wrote suggestions to: {os.path.relpath(out_dir, ROOT)}")


if __name__ == "__main__":
    main()
