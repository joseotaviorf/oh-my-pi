"""
Backfill missing hive-style partitions in AWS Glue for parquet/json tables.

Databricks writes partition folders to S3 and registers them in the Spark
metastore, but Glue only receives partition entries when
``GlueMetastoreService.add_partitions`` / ``repair_table_partitions`` run.
Use this job after enabling Glue partition sync or to repair historical gaps.

Example (single table)::

    python sync_glue_partitions.py raw_ebdb_listing --table-name house_listing

Example (all partitioned tables in a database)::

    python sync_glue_partitions.py raw_ebdb_listing --all-tables
"""

from __future__ import annotations

import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.glue_catalog_helper import GlueCatalogHelper
from bietlejuice.services.metastore_services.glue_metastore_service import (
    GlueMetastoreService,
)

JOB_NAME = "sync_glue_partitions"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _partitioned_table_names(glue_client, database_name: str) -> list[str]:
    names: list[str] = []
    paginator = glue_client.conn.get_paginator("get_tables")
    for page in paginator.paginate(DatabaseName=database_name):
        for table in page.get("TableList", []):
            if table.get("PartitionKeys"):
                names.append(table["Name"])
    return sorted(names)


def repair_glue_partitions(
    database_name: str,
    table_name: str | None,
    all_tables: bool,
) -> None:
    if not GlueCatalogHelper.is_glue_catalog_enabled():
        raise RuntimeError(
            "Glue catalog sync is disabled. Set GLUE_ASSUME_ROLE_ARN or "
            "configure AWS credentials before running this job."
        )

    glue_client = GlueCatalogHelper.get_glue_client()
    glue_service = GlueMetastoreService(glue_client)

    if all_tables:
        table_names = _partitioned_table_names(glue_client, database_name)
    elif table_name:
        table_names = [table_name]
    else:
        raise ValueError("Provide --table-name or --all-tables")

    logger.info(
        f"m=repair_glue_partitions, database={database_name}, "
        f"table_count={len(table_names)}, msg=starting Glue partition backfill"
    )

    failures: list[tuple[str, Exception]] = []
    for name in table_names:
        try:
            glue_service.repair_table_partitions(database_name, name)
        except Exception as exc:
            logger.error(
                f"m=repair_glue_partitions, table={database_name}.{name}, "
                f"error={exc}, msg=partition repair failed"
            )
            failures.append((name, exc))

    if failures:
        failed_tables = ", ".join(name for name, _ in failures)
        raise RuntimeError(f"Glue partition backfill failed for: {failed_tables}")

    logger.info(
        f"m=repair_glue_partitions, database={database_name}, "
        f"table_count={len(table_names)}, msg=Glue partition backfill completed"
    )


def main() -> None:
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("database_name", type=str, help="Glue / Spark database name")
    parser.add_argument(
        "--table-name",
        type=str,
        dest="table_name",
        required=False,
        help="Single table to repair",
    )
    parser.add_argument(
        "--all-tables",
        nargs="?",
        dest="all_tables",
        required=False,
        default=False,
        const=True,
        help="Repair every partitioned table in the database",
    )
    args = parser.parse_args()

    repair_glue_partitions(
        database_name=args.database_name,
        table_name=args.table_name,
        all_tables=bool(args.all_tables),
    )


if __name__ == "__main__":
    main()
