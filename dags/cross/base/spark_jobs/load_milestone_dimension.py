"""Shared Spark job: load one milestone dimension table from many strategy SQLs.

Platform entrypoint for ``workflow.type: milestone_delta`` (and callable via
``load_spark_job: load_milestone_dimension``).

Grain keys are consumer-chosen via ``--merge-on`` (must include
``milestone_type``). Domain sticky carries via ``--sticky-columns`` or metadata
``milestones.sticky_columns``. All ``queries/<layer>/<table>/milestones/*.sql``
strategies MERGE into the **same** target Delta table.
"""

from __future__ import annotations

import json
from argparse import ArgumentParser, Namespace
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.milestones.contract import MilestoneTableSpec
from bietlejuice.milestones.orchestrator import run_all_milestones
from bietlejuice.milestones.registry import load_milestones_from_metadata_yaml

JOB_NAME = "load_milestone_dimension"
logger = QuintoAndarLogger(JOB_NAME)


def _parse_json_list(raw: Optional[str]) -> Optional[List[str]]:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text or text.lower() in {"null", "none", "undefined"}:
        return None
    parsed = json.loads(text)
    if parsed is None:
        return None
    if not isinstance(parsed, list):
        raise ValueError(
            f"m=_parse_json_list, msg=Expected JSON list, got {type(parsed).__name__}"
        )
    return [str(item) for item in parsed]


def parse_args(argv: Optional[list] = None) -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("bucket")
    parser.add_argument("dag_name")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument(
        "--layer",
        default="dw",
        help="Query/metadata layer folder (default: dw)",
    )
    parser.add_argument(
        "--merge-on",
        required=True,
        help='JSON list of MERGE keys; must include "milestone_type"',
    )
    parser.add_argument(
        "--sticky-columns",
        default=None,
        help="JSON list of sticky carry columns (optional; metadata can also set)",
    )
    parser.add_argument(
        "--milestones-to-run",
        default=None,
        help="JSON list of registry keys to run; omit/null = all",
    )
    parser.add_argument(
        "--bootstrap-milestones",
        default=None,
        help="JSON list of registry keys that force full source scan",
    )
    parser.add_argument(
        "--strategies-root",
        default=None,
        help="Override local strategies directory (tests / local runs)",
    )
    parser.add_argument(
        "--metadata-file",
        default=None,
        help="Override path to table metadata YAML (tests / local runs)",
    )
    return parser.parse_args(argv)


def _sql_string_list(values: Sequence[str]) -> str:
    escaped = []
    for value in values:
        text = str(value).replace("'", "''")
        escaped.append(f"'{text}'")
    return ", ".join(escaped)


def _default_strategies_root(dag_name: str, layer: str, table_name: str) -> str:
    from bietlejuice.base.service.dag_packages_path_service import (
        DAGPackagesPathService,
    )

    dag_path = DAGPackagesPathService.get_dag_path(dag_name)
    if dag_path:
        return str(Path(dag_path) / "queries" / layer / table_name / "milestones")
    # Repo-relative fallback when running unit tests outside Airflow packaging.
    repo_guess = Path(__file__).resolve().parents[4] / "dags"
    # Prefer explicit --strategies-root in tests.
    return str(repo_guess)


def _load_metadata_content(
    dag_name: str, layer: str, table_name: str, metadata_file: Optional[str]
) -> str:
    if metadata_file:
        return Path(metadata_file).read_text(encoding="utf-8")

    from bietlejuice.base.service.dag_packages_path_service import (
        DAGPackagesPathService,
    )

    dag_path = DAGPackagesPathService.get_dag_path(dag_name)
    if dag_path:
        path = Path(dag_path) / "metadata" / layer / f"{table_name}.yml"
        if path.is_file():
            return path.read_text(encoding="utf-8")

    raise FileNotFoundError(
        f"m=_load_metadata_content, dag={dag_name}, layer={layer}, "
        f"table={table_name}, msg=metadata YAML not found"
    )


def _resolve_sticky(
    cli_sticky: Optional[List[str]], metadata_sticky: Tuple[str, ...]
) -> Tuple[str, ...]:
    if cli_sticky is not None:
        return tuple(cli_sticky)
    return metadata_sticky


def main(args: Namespace) -> None:
    from bietlejuice.clients.db_clients import SparkClient
    from bietlejuice.loaders.delta_loader import DeltaLoader
    from bietlejuice.services.metastore_services import MetastoreServiceFactory

    merge_on = _parse_json_list(args.merge_on)
    if not merge_on:
        raise ValueError("m=main, msg=--merge-on is required and must be a JSON list")

    metadata_content = _load_metadata_content(
        args.dag_name, args.layer, args.table_name, args.metadata_file
    )
    registry, metadata_sticky = load_milestones_from_metadata_yaml(metadata_content)
    sticky = _resolve_sticky(_parse_json_list(args.sticky_columns), metadata_sticky)
    spec = MilestoneTableSpec.from_merge_on(merge_on, sticky_columns=sticky)

    strategies_root = args.strategies_root or _default_strategies_root(
        args.dag_name, args.layer, args.table_name
    )

    spark_client = SparkClient(app_name=JOB_NAME)
    spark = spark_client.conn
    metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )

    database_name = f"dw_{args.schema}" if args.layer == "dw" else args.schema
    full_table = f"{database_name}.{args.table_name}"
    path = f"s3://{args.bucket}/{args.schema}/{args.table_name}"

    milestones_to_run = _parse_json_list(args.milestones_to_run)
    bootstrap_milestones = _parse_json_list(args.bootstrap_milestones)
    logger.info(
        "m=main, table=%s, merge_on=%s, sticky=%s, strategies_root=%s, "
        "milestones_to_run=%s, bootstrap_milestones=%s",
        full_table,
        list(spec.merge_on),
        list(spec.sticky_columns),
        strategies_root,
        milestones_to_run,
        bootstrap_milestones,
    )

    batch, bootstrap_types = run_all_milestones(
        spark,
        registry,
        full_table,
        strategies_root,
        dag_name=args.dag_name,
        spec=spec,
        milestones_to_run=milestones_to_run,
        bootstrap_milestones=bootstrap_milestones,
        layer=args.layer,
        table_name=args.table_name,
    )

    delete_orphans = None
    if bootstrap_types:
        delete_orphans = (
            f"target.milestone_type IN ({_sql_string_list(bootstrap_types)})"
        )

    metastore_service.create_database(database_name)
    DeltaLoader(spark).load_table(
        table_name=full_table,
        path=path,
        source_df=batch,
        merge_on=list(spec.merge_on),
        when_matched_update_condition=None,
        when_not_matched_by_source_delete_condition=delete_orphans,
    )
    metastore_service.refresh_table(database_name, args.table_name)
    logger.info(
        "m=main, table=%s, bootstrap_types=%s, msg=merge complete",
        full_table,
        bootstrap_types,
    )


if __name__ == "__main__":
    main(parse_args())
