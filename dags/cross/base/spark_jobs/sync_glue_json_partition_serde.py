"""
Backfill Glue JSON table and partition metadata for EMR compatibility.

Does two things per JSON table (emr-cli friendly):

1. **Column types** — coerce fragile Glue types to ``string``: ``timestamp`` and
   ``date`` (``Timestamp.valueOf`` rejects ISO-8601 ``T`` / ``Z`` and OpenX has
   no ``timestamp.formats``) plus ``decimal`` (OpenX has no decimal
   ObjectInspector, so Hive's blind-casts the JSON value and every row raises
   ``ClassCastException: String -> HiveDecimal``). Integral and floating types
   have OpenX inspectors that parse the JSON string, and
   ``array`` / ``struct`` / ``map`` are read natively, so both stay typed.
2. **Partition SerDe and columns** — for partitioned tables, align partition
   ``SerdeInfo`` and ``Columns`` with the table StorageDescriptor. Partitions
   carry their own copies, so a table-only change leaves them unreadable.
   Direction-agnostic: whatever the table declares becomes the target.

The common case is ``--skip-type-coerce``: after the tables themselves have been
re-registered by their production DAGs, this pushes the table's SerDe down onto
every existing partition.

Intended to run on EMR via emr-cli::

    # Preview partition SerDe alignment for one database:
    emr-cli transient \\
      --name glue-json-serde-dry-run \\
      --uri s3://.../sync_glue_json_partition_serde.py \\
      --job-args '--skip-type-coerce --dry-run --database datalake_cyber_raw' \\
      --core-instance-count 1 \\
      --no-use-spot \\
      --wait --follow-logs

    # Apply across every database:
    emr-cli transient \\
      --name glue-json-serde \\
      --uri s3://.../sync_glue_json_partition_serde.py \\
      --job-args '--skip-type-coerce --all-databases' \\
      --core-instance-count 1 \\
      --no-use-spot \\
      --wait --follow-logs

Flags:

* ``--skip-type-coerce`` — only sync partition SerDe
* ``--skip-partition-serde`` — only coerce fragile column types
"""

from __future__ import annotations

import logging
from argparse import ArgumentParser
from typing import Dict, List, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.glue_catalog_helper import GlueCatalogHelper
from bietlejuice.services.metastore_services.glue_metastore_service import (
    GlueMetastoreService,
)
from bietlejuice.services.metastore_services.glue_partition_utils import (
    is_json_glue_table,
)

JOB_NAME = "sync_glue_json_partition_serde"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _json_table_names(
    glue_client,
    database_name: str,
    *,
    partitioned_only: bool = False,
) -> List[str]:
    names: List[str] = []
    paginator = glue_client.conn.get_paginator("get_tables")
    for page in paginator.paginate(DatabaseName=database_name):
        for table in page.get("TableList", []):
            if not is_json_glue_table(table):
                continue
            if partitioned_only and not table.get("PartitionKeys"):
                continue
            names.append(table["Name"])
    return sorted(names)


def _empty_totals() -> Dict[str, int]:
    return {
        "tables_scanned": 0,
        "columns_scanned": 0,
        "columns_updated": 0,
        "partitions_scanned": 0,
        "partitions_updated": 0,
        "tables_skipped": 0,
        "errors": 0,
    }


def sync_glue_json_partition_serde(
    *,
    all_databases: bool,
    database_name: Optional[str],
    table_name: Optional[str],
    dry_run: bool,
    skip_type_coerce: bool = False,
    skip_partition_serde: bool = False,
) -> Dict[str, int]:
    if not GlueCatalogHelper.is_glue_catalog_enabled():
        raise RuntimeError(
            "Glue catalog sync is disabled. Set GLUE_ASSUME_ROLE_ARN or "
            "configure AWS credentials before running this job."
        )

    if skip_type_coerce and skip_partition_serde:
        raise ValueError(
            "Cannot set both --skip-type-coerce and --skip-partition-serde"
        )

    glue_client = GlueCatalogHelper.get_glue_client()
    glue_service = GlueMetastoreService(glue_client)
    totals = _empty_totals()

    if table_name and not database_name:
        raise ValueError("--table-name requires --database")

    if all_databases:
        databases = sorted(glue_client.get_database_names())
    elif database_name:
        databases = [database_name]
    else:
        raise ValueError("Provide --all-databases or --database")

    logger.info(
        f"m=sync_glue_json_partition_serde, database_count={len(databases)}, "
        f"dry_run={dry_run}, skip_type_coerce={skip_type_coerce}, "
        f"skip_partition_serde={skip_partition_serde}, "
        "msg=starting JSON SerDe + fragile type backfill"
    )

    failures: List[tuple[str, Exception]] = []
    for db_name in databases:
        if table_name:
            table_names = [table_name]
        elif skip_type_coerce:
            # Partition SerDe only needs partitioned tables.
            table_names = _json_table_names(glue_client, db_name, partitioned_only=True)
        else:
            # Type coerce covers all JSON tables; SerDe step no-ops if unpartitioned.
            table_names = _json_table_names(
                glue_client, db_name, partitioned_only=False
            )

        for name in table_names:
            totals["tables_scanned"] += 1
            qualified = f"{db_name}.{name}"
            try:
                if not skip_type_coerce:
                    type_result = glue_service.coerce_json_table_column_types(
                        db_name, name, dry_run=dry_run
                    )
                    totals["columns_scanned"] += type_result.get("scanned", 0)
                    totals["columns_updated"] += type_result.get("updated", 0)
                    totals["tables_skipped"] += type_result.get("skipped", 0)
                    totals["errors"] += type_result.get("errors", 0)

                if not skip_partition_serde:
                    serde_result = glue_service.sync_json_partition_serde(
                        db_name, name, dry_run=dry_run
                    )
                    totals["partitions_scanned"] += serde_result.get("scanned", 0)
                    totals["partitions_updated"] += serde_result.get("updated", 0)
                    totals["tables_skipped"] += serde_result.get("skipped", 0)
                    totals["errors"] += serde_result.get("errors", 0)
            except Exception as exc:
                logger.error(
                    f"m=sync_glue_json_partition_serde, table={qualified}, "
                    f"error={exc}, msg=JSON SerDe/type backfill failed"
                )
                totals["errors"] += 1
                failures.append((qualified, exc))

    logger.info(
        f"m=sync_glue_json_partition_serde, "
        f"tables_scanned={totals['tables_scanned']}, "
        f"columns_scanned={totals['columns_scanned']}, "
        f"columns_updated={totals['columns_updated']}, "
        f"partitions_scanned={totals['partitions_scanned']}, "
        f"partitions_updated={totals['partitions_updated']}, "
        f"tables_skipped={totals['tables_skipped']}, "
        f"errors={totals['errors']}, dry_run={dry_run}, "
        "msg=JSON SerDe + fragile type backfill completed"
    )

    if failures:
        failed_tables = ", ".join(name for name, _ in failures)
        raise RuntimeError(f"Glue JSON SerDe/type backfill failed for: {failed_tables}")

    return totals


def main() -> None:
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument(
        "--all-databases",
        action="store_true",
        dest="all_databases",
        help="Scan every Glue database for JSON tables",
    )
    parser.add_argument(
        "--database",
        type=str,
        dest="database_name",
        required=False,
        help="Limit sync to one Glue database",
    )
    parser.add_argument(
        "--table-name",
        type=str,
        dest="table_name",
        required=False,
        help="Limit sync to one table (requires --database)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        dest="dry_run",
        help="Report changes without calling Glue update",
    )
    parser.add_argument(
        "--skip-type-coerce",
        action="store_true",
        dest="skip_type_coerce",
        help="Only sync partition SerDe; do not rewrite column types",
    )
    parser.add_argument(
        "--skip-partition-serde",
        action="store_true",
        dest="skip_partition_serde",
        help="Only coerce fragile column types; do not sync partition SerDe",
    )
    args = parser.parse_args()

    sync_glue_json_partition_serde(
        all_databases=bool(args.all_databases),
        database_name=args.database_name,
        table_name=args.table_name,
        dry_run=bool(args.dry_run),
        skip_type_coerce=bool(args.skip_type_coerce),
        skip_partition_serde=bool(args.skip_partition_serde),
    )


if __name__ == "__main__":
    main()
