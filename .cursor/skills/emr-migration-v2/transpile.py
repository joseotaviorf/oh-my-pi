"""Transpilation orchestrator for the EMR migration skill.

Discovers SQL files in a DAG scope, transpiles Databricks-only constructs
using SQLGlot, validates syntax, and generates three validation DAGs.

Usage (from repo root):
  # Transpile only (dry run):
  uv run --directory packages/bietlejuice-compiler python \
    .cursor/skills/emr-migration-v2/transpile.py \
    --scope fintech/enrich_velo

  # Transpile + generate DAGs (end-to-end):
  uv run --directory packages/bietlejuice-compiler python \
    .cursor/skills/emr-migration-v2/transpile.py \
    --scope fintech/enrich_velo --generate-dags

  # Multiple DAGs:
  uv run --directory packages/bietlejuice-compiler python \
    .cursor/skills/emr-migration-v2/transpile.py \
    --scope fintech/enrich_velo,agents/enrich_agent --generate-dags
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import uuid
from pathlib import Path
from typing import List, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "packages" / "bietlejuice-compiler" / "src"))

from bietlejuice.transpiler.databricks_to_spark import (
    DatabricksToSparkTranspiler,
    needs_transpilation,
)
from bietlejuice.transpiler.syntax_validator import validate_spark_syntax

from dag_generator import generate_dags
from models import DagTranspileReport, MigrationScope, TableTranspileResult


def discover_sql_files(domain: str, dag_name: str) -> List[Tuple[str, str, str]]:
    """Find SQL files for a DAG. Returns list of (table_name, layer, abs_path)."""
    dag_dir = REPO_ROOT / "dags" / domain / dag_name / "queries"
    results = []
    if not dag_dir.exists():
        return results

    for layer_dir in sorted(dag_dir.iterdir()):
        if not layer_dir.is_dir():
            continue
        layer = layer_dir.name
        for sql_file in sorted(layer_dir.glob("*.sql")):
            table_name = sql_file.stem
            results.append((table_name, layer, str(sql_file)))

    return results


def transpile_dag(scope: MigrationScope, run_id: str) -> DagTranspileReport:
    """Transpile all SQL files for a single DAG scope."""
    report = DagTranspileReport(scope=scope, run_id=run_id)
    transpiler = DatabricksToSparkTranspiler()

    sql_files = discover_sql_files(scope.domain, scope.dag_name)
    if not sql_files:
        return report

    for table_name, layer, sql_path in sql_files:
        with open(sql_path, encoding="utf-8") as f:
            original_sql = f.read()

        table_result = TableTranspileResult(
            table_name=table_name,
            layer=layer,
            original_path=sql_path,
        )

        findings = needs_transpilation(original_sql)
        if not findings:
            table_result.needs_transpile = False
            table_result.transpiled = original_sql
            table_result.syntax_valid = True
            report.tables.append(table_result)
            continue

        table_result.needs_transpile = True
        table_result.findings = findings

        result = transpiler.transpile_sql(original_sql)
        if result.error:
            table_result.error = result.error
            report.tables.append(table_result)
            continue

        valid, syntax_error = validate_spark_syntax(result.transpiled)
        if not valid:
            table_result.error = f"Syntax validation failed: {syntax_error}"
            table_result.transpiled = result.transpiled
            report.tables.append(table_result)
            continue

        table_result.transpiled = result.transpiled
        table_result.syntax_valid = True
        report.tables.append(table_result)

    return report


def print_report(report: DagTranspileReport) -> None:
    print(f"\n{'=' * 60}")
    print(f"TRANSPILATION REPORT: {report.scope.domain}/{report.scope.dag_name}")
    print(f"Run ID: {report.run_id}")
    print(f"{'=' * 60}")
    print(
        f"Total: {len(report.tables)} | Pass: {report.passed} | "
        f"Skip: {report.skipped} | Fail: {report.failed}"
    )
    print(f"{'-' * 60}")

    for t in report.tables:
        status_icon = {"PASS": "+", "SKIP": "-", "FAIL": "!"}[t.status]
        transpile_note = ""
        if not t.needs_transpile:
            transpile_note = " (already compatible)"
        elif t.error:
            transpile_note = f" ({t.error[:60]})"
        print(f"  [{status_icon}] {t.layer}/{t.table_name}{transpile_note}")
        for f in t.findings:
            print(f"      {f}")

    print(f"{'=' * 60}\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Transpile Databricks SQL to Spark 3.5 for EMR migration"
    )
    parser.add_argument(
        "--scope",
        required=True,
        help="Comma-separated domain/dag_name list (e.g., fintech/enrich_docx,agents/enrich_agent)",
    )
    parser.add_argument(
        "--run-id",
        default=None,
        help="Migration run ID (auto-generated if not provided)",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory to write transpiled SQL (default: dags/platform/)",
    )
    parser.add_argument(
        "--generate-dags",
        action="store_true",
        help="Generate the three validation DAGs (twin/emr/comparison) after transpilation",
    )
    args = parser.parse_args()

    run_id = args.run_id or str(uuid.uuid4())
    scopes = MigrationScope.parse_list(args.scope)
    output_base = (
        Path(args.output_dir) if args.output_dir else REPO_ROOT / "dags" / "platform"
    )

    all_reports = []
    for scope in scopes:
        report = transpile_dag(scope, run_id)
        print_report(report)

        if report.failed > 0:
            print(
                f"WARNING: {report.failed} table(s) failed transpilation for "
                f"{scope.domain}/{scope.dag_name}"
            )

        if args.generate_dags:
            if report.failed > 0:
                print(
                    f"SKIPPING DAG generation for {scope.domain}/{scope.dag_name} "
                    f"due to {report.failed} failed table(s)"
                )
            elif not report.tables_to_validate:
                print(
                    f"SKIPPING DAG generation for {scope.domain}/{scope.dag_name} "
                    f"— no tables to validate"
                )
            else:
                created = generate_dags(report, output_base=output_base)
                print(f"Generated DAGs:")
                for path in created:
                    print(f"  {path}")
        else:
            dag_output = (
                output_base
                / f"migration_emr_{scope.scope_id}"
                / "queries"
                / "migration"
            )
            dag_output.mkdir(parents=True, exist_ok=True)
            for t in report.tables_to_validate:
                if t.transpiled:
                    out_file = dag_output / f"{t.table_name}.sql"
                    out_file.write_text(t.transpiled, encoding="utf-8")

        all_reports.append(report)

    print(f"\nRun ID: {run_id}")
    print(f"Output: {output_base}")
    total_pass = sum(r.passed for r in all_reports)
    total_skip = sum(r.skipped for r in all_reports)
    total_fail = sum(r.failed for r in all_reports)
    print(
        f"Overall: {total_pass} transpiled, {total_skip} already compatible, {total_fail} failed"
    )

    if args.generate_dags and total_fail == 0:
        print("\nDAGs ready. Next steps:")
        print(
            f"  1. Review generated files under {output_base}/migration_*_{all_reports[0].scope.scope_id if all_reports else ''}*/"
        )
        print("  2. Run: make create-dag-files")
        print(
            "  3. Deploy to Forno and trigger both twin and emr DAGs (any order, comparison fires automatically)"
        )

    if total_fail > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
