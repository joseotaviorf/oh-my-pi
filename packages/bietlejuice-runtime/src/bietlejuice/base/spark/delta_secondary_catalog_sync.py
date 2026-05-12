"""
Secondary catalog sync after a Delta write that bypasses table loader pipelines.

Mirrors the post-``refresh_table`` step in ``DeltaTableLoaderPipeline``: refresh Spark
cache, derive schema from the written DataFrame, then
``CatalogStrategyResolver.sync_to_secondary_catalog`` (Glue on Databricks, UC REST on EMR).
"""

from __future__ import annotations

from typing import List, Sequence

from bietlejuice.base.spark.catalog_strategy_resolver import CatalogStrategyResolver
from bietlejuice.services.schema_service import SchemaService


def sync_delta_write_to_secondary_catalog(
    spark,
    full_table_name: str,
    table_location_s3: str,
    source_df,
    partition_col_names: List[str],
) -> None:
    """Refresh table metadata in Spark, then sync table DDL to the secondary catalog.

    :param spark: Active Spark session.
    :param full_table_name: Two-part name ``database.table``.
    :param table_location_s3: Table root path (``s3://`` or ``s3a://``).
    :param source_df: DataFrame that was written (used for Glue/UC column types).
    :param partition_col_names: Hive partition column names; empty if not partitioned.
    """
    if "." not in full_table_name:
        raise ValueError(
            f"sync_delta_write_to_secondary_catalog: expected 'db.table', got {full_table_name!r}"
        )
    database_name, _, table_name = full_table_name.partition(".")
    spark.sql(f"REFRESH TABLE {database_name}.{table_name}")
    table_schema = SchemaService.get_schema_from_dataframe(source_df)
    CatalogStrategyResolver.sync_to_secondary_catalog(
        database_name=database_name,
        table_name=table_name,
        table_location=table_location_s3,
        table_schema=table_schema,
        partitions=list(partition_col_names),
        format_str="DELTA",
    )


def partition_columns_present(source_df, candidates: Sequence[str]) -> List[str]:
    """Return members of ``candidates`` that exist as columns on ``source_df`` (stable order)."""
    cols = set(source_df.columns)
    return [name for name in candidates if name in cols]
