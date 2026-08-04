"""
Sync Glue JSON partition SerDe to match the table StorageDescriptor.

After tables are re-registered with HCatalog JsonSerDe + ``timestamp.formats``,
existing partitions may still point at OpenX JsonSerDe. This job updates
(does not drop/recreate) those partitions in place via Glue
``batch_update_partition``.

Intended to run on EMR via emr-cli::

    emr-cli transient \\
      --name glue-json-partition-serde-dry-run \\
      --uri s3://.../sync_glue_json_partition_serde.py \\
      --job-args '--all-databases --dry-run' \\
      --core-instance-count 1 \\
      --no-use-spot \\
      --wait --follow-logs
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


def _json_partitioned_table_names(glue_client, database_name: str) -> List[str]:
    names: List[str] = []
    paginator = glue_client.conn.get_paginator("get_tables")
    for page in paginator.paginate(DatabaseName=database_name):
        for table in page.get("TableList", []):
            if not table.get("PartitionKeys"):
                continue
            if is_json_glue_table(table):
                names.append(table["Name"])
    return sorted(names)


def _empty_totals() -> Dict[str, int]:
    return {
        "tables_scanned": 0,
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
) -> Dict[str, int]:
    if not GlueCatalogHelper.is_glue_catalog_enabled():
        raise RuntimeError(
            "Glue catalog sync is disabled. Set GLUE_ASSUME_ROLE_ARN or "
            "configure AWS credentials before running this job."
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
        f"dry_run={dry_run}, msg=starting JSON partition SerDe sync"
    )

    failures: List[tuple[str, Exception]] = []
    for db_name in databases:
        if table_name:
            table_names = [table_name]
        else:
            table_names = _json_partitioned_table_names(glue_client, db_name)

        for name in table_names:
            totals["tables_scanned"] += 1
            qualified = f"{db_name}.{name}"
            try:
                result = glue_service.sync_json_partition_serde(
                    db_name, name, dry_run=dry_run
                )
                totals["partitions_scanned"] += result.get("scanned", 0)
                totals["partitions_updated"] += result.get("updated", 0)
                totals["tables_skipped"] += result.get("skipped", 0)
                totals["errors"] += result.get("errors", 0)
            except Exception as exc:
                logger.error(
                    f"m=sync_glue_json_partition_serde, table={qualified}, "
                    f"error={exc}, msg=partition SerDe sync failed"
                )
                totals["errors"] += 1
                failures.append((qualified, exc))

    logger.info(
        f"m=sync_glue_json_partition_serde, "
        f"tables_scanned={totals['tables_scanned']}, "
        f"partitions_scanned={totals['partitions_scanned']}, "
        f"partitions_updated={totals['partitions_updated']}, "
        f"tables_skipped={totals['tables_skipped']}, "
        f"errors={totals['errors']}, dry_run={dry_run}, "
        "msg=JSON partition SerDe sync completed"
    )

    if failures:
        failed_tables = ", ".join(name for name, _ in failures)
        raise RuntimeError(
            f"Glue JSON partition SerDe sync failed for: {failed_tables}"
        )

    return totals


def main() -> None:
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument(
        "--all-databases",
        action="store_true",
        dest="all_databases",
        help="Scan every Glue database for partitioned JSON tables",
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
        help="Report partitions that would be updated without calling Glue update",
    )
    args = parser.parse_args()

    sync_glue_json_partition_serde(
        all_databases=bool(args.all_databases),
        database_name=args.database_name,
        table_name=args.table_name,
        dry_run=bool(args.dry_run),
    )


if __name__ == "__main__":
    main()
