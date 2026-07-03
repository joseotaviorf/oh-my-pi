#!/usr/bin/env python3
"""Generate 1:1 Gen7 validation blocks for QuintoML Wonka feature sets.

Maps each prod wonka_cluster topology to a wonka_consolidation_* Graviton Gen7
validation spec without resizing. Writes validation: into jobs/wonka/*/configs/prod.yml.

Usage:
  ENVIRONMENT=prod uv run python scripts/generate_wonka_validation_blocks.py --dry-run
  ENVIRONMENT=prod uv run python scripts/generate_wonka_validation_blocks.py --write
  ENVIRONMENT=prod uv run python scripts/generate_wonka_validation_blocks.py --check
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
COMPILER_ROOT = REPO_ROOT / "packages" / "bietlejuice-compiler"
CORE_SRC = REPO_ROOT / "packages" / "bietlejuice-core" / "src"

for path in (COMPILER_ROOT, COMPILER_ROOT / "src", CORE_SRC):
    path_str = str(path)
    if path_str not in sys.path:
        sys.path.insert(0, path_str)

from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (  # noqa: E402
    build_validation_cluster_spec,
    is_emr_prod_cluster_args,
)
from scripts.ci_cd.airflow_dag_builder.wonka_config_paths import (  # noqa: E402
    DEFAULT_QUINTOML_ROOT,
    iter_wonka_prod_configs,
    wonka_airflow_dag_id,
)
from scripts.ci_cd.airflow_dag_builder.wonka_validation_config import (  # noqa: E402
    load_wonka_prod_declaration,
    validation_doc_from_spec,
    write_validation_to_wonka_prod_yml,
)

CSV_FIELDS = (
    "prod_yml_path",
    "airflow_dag_id",
    "status",
    "validation_preset",
    "spark_version_override",
    "detail",
)


@dataclass
class GenerationResult:
    prod_yml_path: Path
    airflow_dag_id: str | None
    status: str
    validation_preset: str | None = None
    spark_version_override: bool = False
    detail: str = ""


def _spark_version_override(
    spec_custom: dict, preset_spark_version: str | None
) -> bool:
    if not spec_custom:
        return False
    prod_spark = spec_custom.get("spark_version")
    if prod_spark is None:
        return False
    if preset_spark_version is None:
        return True
    return str(prod_spark).strip() != str(preset_spark_version).strip()


def generate_for_path(prod_yml_path: Path) -> GenerationResult:
    declaration = load_wonka_prod_declaration(prod_yml_path)
    if declaration is None:
        return GenerationResult(
            prod_yml_path, None, "failed", detail="yaml_parse_error"
        )

    dag_id = wonka_airflow_dag_id(declaration)
    cluster_args = declaration.get("cluster")
    if not isinstance(cluster_args, dict):
        return GenerationResult(
            prod_yml_path, dag_id, "failed", detail="missing_cluster_section"
        )

    if is_emr_prod_cluster_args(cluster_args):
        return GenerationResult(prod_yml_path, dag_id, "skipped_emr")

    try:
        spec = build_validation_cluster_spec(
            cluster_args=cluster_args,
            declaration=declaration,
        )
    except ValueError as exc:
        return GenerationResult(
            prod_yml_path,
            dag_id,
            "skipped_unmapped",
            detail=str(exc),
        )
    except Exception as exc:  # noqa: BLE001
        return GenerationResult(
            prod_yml_path,
            dag_id,
            "failed",
            detail=f"{type(exc).__name__}: {exc}",
        )

    if spec is None:
        return GenerationResult(prod_yml_path, dag_id, "skipped_no_diff")

    custom = spec.custom_configurations or {}
    spark_override = _spark_version_override(custom, "16.4.x-scala2.12")
    return GenerationResult(
        prod_yml_path,
        dag_id,
        "eligible",
        validation_preset=spec.cluster_type,
        spark_version_override=spark_override,
    )


def _filter_paths(
    paths: list[Path],
    dag_filter: set[str] | None,
) -> list[Path]:
    if not dag_filter:
        return paths
    filtered: list[Path] = []
    for path in paths:
        declaration = load_wonka_prod_declaration(path)
        if declaration is None:
            continue
        dag_id = wonka_airflow_dag_id(declaration)
        if dag_id is None:
            continue
        feature_set = dag_id.removeprefix("quintoml.wonka.")
        kebab_dir = path.parent.parent.name
        if (
            feature_set in dag_filter
            or kebab_dir in dag_filter
            or dag_id in dag_filter
            or f"{dag_id}__validation" in dag_filter
        ):
            filtered.append(path)
    return filtered


def _write_spec(prod_yml_path: Path, result: GenerationResult) -> None:
    declaration = load_wonka_prod_declaration(prod_yml_path)
    if declaration is None or not isinstance(declaration.get("cluster"), dict):
        raise ValueError(f"Cannot reload declaration for {prod_yml_path}")
    spec = build_validation_cluster_spec(
        cluster_args=declaration["cluster"],
        declaration=declaration,
    )
    if spec is None:
        raise ValueError(f"No validation spec for {prod_yml_path}")
    write_validation_to_wonka_prod_yml(
        prod_yml_path,
        validation_doc_from_spec(spec),
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true", help="Print summary only")
    mode.add_argument("--write", action="store_true", help="Write validation blocks")
    mode.add_argument(
        "--check",
        action="store_true",
        help="Exit 1 when on-disk validation differs from generator output",
    )
    parser.add_argument(
        "--quintoml-root",
        type=Path,
        default=DEFAULT_QUINTOML_ROOT,
        help=f"QuintoML repo root (default {DEFAULT_QUINTOML_ROOT})",
    )
    parser.add_argument(
        "--dags",
        metavar="NAMES",
        help="Comma-separated feature sets (snake, kebab, or full dag id)",
    )
    parser.add_argument(
        "--report-csv",
        type=Path,
        help="Optional CSV report path",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    dag_filter = (
        {part.strip() for part in args.dags.split(",") if part.strip()}
        if args.dags
        else None
    )
    paths = _filter_paths(iter_wonka_prod_configs(args.quintoml_root), dag_filter)
    if not paths:
        print("No Wonka prod.yml files matched.", file=sys.stderr)
        return 1

    results: list[GenerationResult] = []
    for path in paths:
        result = generate_for_path(path)
        results.append(result)
        if args.write and result.status == "eligible":
            _write_spec(path, result)

    counts: dict[str, int] = {}
    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1

    print(
        f"Wonka validation generation: {len(results)} configs — "
        + ", ".join(f"{status}={count}" for status, count in sorted(counts.items()))
    )
    for result in results:
        if result.status not in ("eligible", "failed", "skipped_unmapped"):
            continue
        print(
            f"  [{result.status}] {result.airflow_dag_id or '?'} "
            f"-> {result.validation_preset or '-'} ({result.detail or result.prod_yml_path.name})"
        )

    if args.report_csv:
        args.report_csv.parent.mkdir(parents=True, exist_ok=True)
        with args.report_csv.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
            writer.writeheader()
            for result in results:
                writer.writerow(
                    {
                        "prod_yml_path": str(result.prod_yml_path),
                        "airflow_dag_id": result.airflow_dag_id or "",
                        "status": result.status,
                        "validation_preset": result.validation_preset or "",
                        "spark_version_override": result.spark_version_override,
                        "detail": result.detail,
                    }
                )

    if args.check:
        # Regenerate expected docs and compare to on-disk validation sections.
        drift = 0
        for result in results:
            if result.status != "eligible":
                continue
            declaration = load_wonka_prod_declaration(result.prod_yml_path)
            if declaration is None:
                drift += 1
                continue
            on_disk = declaration.get("validation")
            spec = build_validation_cluster_spec(
                cluster_args=declaration["cluster"],
                declaration=declaration,
            )
            expected = validation_doc_from_spec(spec) if spec else None
            if on_disk != expected:
                drift += 1
                print(f"DRIFT: {result.prod_yml_path}", file=sys.stderr)
        return 1 if drift else 0

    return 0 if counts.get("failed", 0) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
