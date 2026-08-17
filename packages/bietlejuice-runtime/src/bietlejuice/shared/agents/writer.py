"""Enrich-layer Delta MERGE and optional temp-view publish helpers."""

from __future__ import annotations

from argparse import Namespace
from typing import FrozenSet, Tuple

from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import resolve_datalake_write_target
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

LAKE_WRITE_MODES: FrozenSet[str] = frozenset({"prod", "write"})


def resolve_write_target(
    args: Namespace,
) -> Tuple[str, str, str, str]:
    """Resolve prod/validation Delta write coordinates for an enrich table."""
    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=args.table_name,
            prod_location=database_location,
            bucket=args.datalake_bucket,
            target_database=getattr(args, "target_database_name", None),
            target_table=getattr(args, "target_table_name", None),
        )
    )
    full_table_name = f"{write_database_name}.{write_table_name}"
    s3_path = f"{write_location}{write_table_name}"
    return full_table_name, s3_path, write_database_name, write_table_name


def write_delta_or_dev_view(
    spark_client: SparkClient,
    result_df: DataFrame,
    args: Namespace,
    *,
    merge_on: Tuple[str, ...],
    partition_by: Tuple[str, ...],
    row_count: int,
    logger: QuintoAndarLogger,
    view_suffix: str,
) -> None:
    """MERGE ``result_df`` into the enrich target, or register a temp view.

    ``run_mode`` ``prod`` or ``write``: lake MERGE. ``dev``: temp view
    ``dev_{table}_{view_suffix}``.
    """
    run_mode = getattr(args, "run_mode", "dev")
    if run_mode not in LAKE_WRITE_MODES:
        if run_mode != "dev":
            raise ValueError(
                f"Invalid run_mode: {run_mode!r}. Expected 'dev', 'prod', or 'write'."
            )
        view_name = f"dev_{args.table_name}_{view_suffix}"
        result_df.createOrReplaceTempView(view_name)
        logger.info(
            f"Dev mode: temp view '{view_name}' ({row_count:,} rows). "
            f"SELECT * FROM {view_name}"
        )
        return

    full_table_name, s3_path, write_database_name, write_table_name = (
        resolve_write_target(args)
    )
    metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )
    metastore_service.create_database(write_database_name)
    DeltaLoader(spark_client.conn).load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=list(partition_by),
        merge_on=list(merge_on),
    )
    metastore_service.refresh_table(write_database_name, write_table_name)
    priv = TablePrivileges.from_environment_default(full_table_name)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()
    logger.info(
        f"m=write_delta_or_dev_view, slice={view_suffix}, table={full_table_name}, "
        f"rows={row_count:,}"
    )
