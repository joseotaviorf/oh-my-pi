"""Read validation_report.json and print failing SQL files with errors.

Designed to be called by Claude Code / Cursor in a fix loop:
1. Run validate_transpiled_sql.py (writes .git/validation_report.json)
2. Run this script to get the list of failures
3. IDE fixes each file using its LLM
4. Re-run validate_transpiled_sql.py to confirm

Usage:
  uv run --no-project python \
    .cursor/skills/emr-migration-v2/fix_from_report.py

  # Output single file for the IDE to fix next:
  uv run --no-project python \
    .cursor/skills/emr-migration-v2/fix_from_report.py --next

  # Output as JSON for programmatic consumption:
  uv run --no-project python \
    .cursor/skills/emr-migration-v2/fix_from_report.py --json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
REPORT_PATH = REPO_ROOT / ".git" / "validation_report.json"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Read validation report and show failures for IDE fixing"
    )
    parser.add_argument(
        "--next",
        action="store_true",
        help="Show only the next file to fix (for iterative IDE loop)",
    )
    parser.add_argument(
        "--json",
        dest="as_json",
        action="store_true",
        help="Output as JSON",
    )
    parser.add_argument(
        "--report",
        default=str(REPORT_PATH),
        help=f"Path to validation report (default: {REPORT_PATH})",
    )
    args = parser.parse_args()

    report_path = Path(args.report)
    if not report_path.exists():
        print(
            "No validation report found. Run validate_transpiled_sql.py first.",
            file=sys.stderr,
        )
        sys.exit(1)

    report = json.loads(report_path.read_text())
    failures = [
        r
        for r in report.get("results", [])
        if r.get("status") in ("fail", "fixed_local")
    ]

    if not failures:
        print("All files pass validation.")
        sys.exit(0)

    if args.as_json:
        if args.next:
            print(json.dumps(failures[0], indent=2))
        else:
            print(json.dumps(failures, indent=2))
        sys.exit(0)

    if args.next:
        f = failures[0]
        sql_path = REPO_ROOT / f["path"]
        print(f"File: {f['path']}")
        print(f"Domain: {f.get('domain', '?')} | Table: {f.get('table', '?')}")
        print(f"Status: {f['status']}")
        print()
        errs = {
            k: f.get(k)
            for k in (
                "spark_error",
                "databricks_error",
                "databricks_explain_error",
                "emr_explain_error",
            )
            if f.get(k)
        }
        if errs:
            print("Errors:")
            for label, err in errs.items():
                print(f"  {label}: {err[:300]}")
        print()
        if sql_path.exists():
            sql = sql_path.read_text()
            print(f"SQL ({len(sql)} chars):")
            print(sql[:2000])
            if len(sql) > 2000:
                print(f"... ({len(sql) - 2000} more chars)")
        sys.exit(0)

    print(f"Failures: {len(failures)} / {report.get('total', '?')}")
    print(f"{'=' * 72}")
    for f in failures:
        errs = []
        if f.get("spark_error"):
            errs.append("spark")
        if f.get("databricks_error"):
            errs.append("databricks")
        if f.get("databricks_explain_error"):
            errs.append("dbx_explain")
        if f.get("emr_explain_error"):
            errs.append("emr_explain")
        err_str = ", ".join(errs) if errs else f["status"]
        print(f"  [{f.get('domain', '?'):>20}] {f.get('table', '?'):<40} ({err_str})")
    print(f"{'=' * 72}")
    print(
        "\nTo fix iteratively, run with --next to get one file at a time,\n"
        "or ask Claude Code: 'fix the next failing SQL from the validation report'"
    )


if __name__ == "__main__":
    main()
