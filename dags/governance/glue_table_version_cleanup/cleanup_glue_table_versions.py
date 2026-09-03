"""
Notebook- and CLI-friendly Glue TABLE_VERSION cleanup.

Uses the default credential chain, an optional ``--worker-role-arn`` (Airflow
worker), and/or an explicit ``--assume-role-arn`` / ``GLUE_ASSUME_ROLE_ARN`` for
notebook or ad-hoc runs. The scheduled Airflow DAG does not set a Glue assume
role by default.

Examples::

    # CLI with worker role only (same as prod Airflow path)
    python cleanup_glue_table_versions.py --dry-run \\
        --worker-role-arn arn:aws:iam::206390561754:role/airflow-prod-role

    # Notebook with explicit Glue role (optional second hop)
    from bietlejuice.services.glue.glue_table_version_cleanup import (
        create_glue_client,
        sweep_glue_table_versions,
    )

    glue_client = create_glue_client(
        role_arn="arn:aws:iam::206390561754:role/databricks-prod-glue-access",
    )
    print(sweep_glue_table_versions(glue_client, dry_run=True).as_dict())
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Optional

from bietlejuice.services.glue.glue_table_version_cleanup import (
    GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV,
    GlueTableVersionCleanupSummary,
    create_glue_client,
    resolve_dry_run,
    sweep_glue_table_versions,
)

DEFAULT_REGION = "us-east-1"
GLUE_ASSUME_ROLE_ARN_ENV = "GLUE_ASSUME_ROLE_ARN"


def run_cleanup(
    *,
    keep_count: int = 1,
    database_prefix: Optional[str] = None,
    database_name: Optional[str] = None,
    table_name: Optional[str] = None,
    dry_run: bool = False,
    max_tables: Optional[int] = None,
    fail_on_error: bool = True,
    role_arn: Optional[str] = None,
    worker_role_arn: Optional[str] = None,
    region: str = DEFAULT_REGION,
) -> GlueTableVersionCleanupSummary:
    glue_client = create_glue_client(
        role_arn=role_arn,
        worker_role_arn=worker_role_arn,
        region=region,
    )
    summary = sweep_glue_table_versions(
        glue_client,
        keep_count=keep_count,
        database_prefix=database_prefix,
        database_name=database_name,
        table_name=table_name,
        dry_run=dry_run,
        max_tables=max_tables,
    )
    if fail_on_error and summary.failures:
        failed_tables = ", ".join(name for name, _ in summary.failures)
        raise RuntimeError(
            f"Glue table version cleanup failed for {len(summary.failures)} "
            f"table(s): {failed_tables}"
        )
    return summary


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser("cleanup_glue_table_versions")
    parser.add_argument("--region", default=DEFAULT_REGION)
    parser.add_argument(
        "--worker-role-arn",
        default=os.environ.get("AIRFLOW_GLUE_WORKER_ROLE_ARN"),
        help="Optional first-hop Airflow worker role (Astro → airflow-prod-role).",
    )
    parser.add_argument(
        "--assume-role-arn",
        default=os.environ.get(GLUE_ASSUME_ROLE_ARN_ENV),
        help=(
            "Optional explicit Glue role (second hop when --worker-role-arn is set, "
            "or single-hop via GlueClient when worker role is omitted). "
            f"Defaults to ${GLUE_ASSUME_ROLE_ARN_ENV} when set."
        ),
    )
    parser.add_argument("--keep-count", type=int, default=1)
    parser.add_argument("--database-prefix", default=None)
    parser.add_argument("--database", default=None)
    parser.add_argument("--table", default=None)
    parser.add_argument("--max-tables", type=int, default=None)
    parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=None,
        help=(
            "Count deletions without calling Glue delete APIs. When omitted, "
            f"falls back to ${GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV}."
        ),
    )
    parser.add_argument(
        "--fail-on-error",
        action=argparse.BooleanOptionalAction,
        default=True,
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = _parse_args(argv)
    if args.dry_run is None:
        dry_run = resolve_dry_run(default=False)
    else:
        dry_run = args.dry_run
    summary = run_cleanup(
        keep_count=args.keep_count,
        database_prefix=args.database_prefix,
        database_name=args.database,
        table_name=args.table,
        dry_run=dry_run,
        max_tables=args.max_tables,
        fail_on_error=args.fail_on_error,
        role_arn=args.assume_role_arn,
        worker_role_arn=args.worker_role_arn,
        region=args.region,
    )
    print(json.dumps(summary.as_dict(), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
