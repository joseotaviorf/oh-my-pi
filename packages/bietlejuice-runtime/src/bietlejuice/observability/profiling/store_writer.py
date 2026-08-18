"""Append-only writer for the ``datalake_observability`` store.

The store is append-only by design (one row per profiled table/partition and
Delta version; read-time dedup by latest version). ``DeltaLoader`` defaults to
an *overwrite*, so it is intentionally not reused here — a plain Delta append is
required so history accumulates.

Tables are created lazily as external Delta tables on first write, partitioned by
``year``/``month``/``day``; subsequent runs append. ``mergeSchema`` allows the
row shape to evolve forward-compatibly (paired with ``metric_schema_version``).

After each append, access is published the same way as ``DeltaTableLoaderPipeline``:
secondary-catalog sync (Glue on Databricks → Trino ``hive`` catalog) and default UC
grants via ``TablePrivileges.from_environment_default``.
"""

from __future__ import annotations

from delta.tables import DeltaTable
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.observability.profiling.store_schemas import (
    PARTITION_COLUMNS,
    PARTITION_METRICS_SCHEMA,
    TABLE_METRICS_SCHEMA,
)

logger = QuintoAndarLogger("ObservabilityStoreWriter")

DATABASE = "datalake_observability"
TABLE_METRICS_TABLE = "profile_table_metrics"
PARTITION_METRICS_TABLE = "profile_partition_metrics"


class ObservabilityStoreWriter:
    """Appends profiling metric rows to the observability store."""

    def __init__(self, spark: SparkSession, base_location: str) -> None:
        self.spark = spark
        self.base_location = base_location.rstrip("/")

    def append_table_metrics(self, records: list[dict]) -> int:
        return self._append(TABLE_METRICS_TABLE, records, TABLE_METRICS_SCHEMA)

    def append_partition_metrics(self, records: list[dict]) -> int:
        return self._append(PARTITION_METRICS_TABLE, records, PARTITION_METRICS_SCHEMA)

    def _append(self, table: str, records: list[dict], schema: StructType) -> int:
        if not records:
            logger.info(f"No rows to append to {DATABASE}.{table}; skipping.")
            return 0
        self.spark.sql(f"CREATE DATABASE IF NOT EXISTS `{DATABASE}`")
        fqtn = f"{DATABASE}.{table}"
        location = f"{self.base_location}/{table}"
        rows = [self._project(record, schema) for record in records]
        dataframe = self.spark.createDataFrame(rows, schema)
        delta_exists = DeltaTable.isDeltaTable(self.spark, location)
        self._ensure_store_table(table, fqtn, location)
        writer = (
            dataframe.write.format("delta").mode("append").option("mergeSchema", "true")
        )
        if self.spark.catalog.tableExists(fqtn) or delta_exists:
            writer.insertInto(fqtn)
        else:
            (
                writer.option("path", location)
                .partitionBy(*PARTITION_COLUMNS)
                .saveAsTable(fqtn)
            )
        logger.info(f"Appended {len(rows)} row(s) to {fqtn} at {location}.")
        self._publish_table_access(table, fqtn, location, dataframe)
        return len(rows)

    def _publish_table_access(
        self, table: str, fqtn: str, location: str, dataframe: DataFrame
    ) -> None:
        """Mirror ``DeltaTableLoaderPipeline.load_and_register`` post-write hooks."""
        from bietlejuice.base.databricks.table_privileges import TablePrivileges
        from bietlejuice.base.spark.catalog_strategy_resolver import (
            CatalogStrategyResolver,
        )
        from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
        from bietlejuice.services.schema_service import SchemaService

        if not self.spark.catalog.tableExists(fqtn):
            return

        table_schema = SchemaService.get_schema_from_dataframe(dataframe)
        try:
            CatalogStrategyResolver.sync_to_secondary_catalog(
                database_name=DATABASE,
                table_name=table,
                table_location=location,
                table_schema=table_schema,
                partitions=PARTITION_COLUMNS,
                format_str="DELTA",
            )
        except Exception as error:
            logger.error(f"Failed to sync {fqtn} to secondary catalog: {error}")

        if not UnityCatalogHelper.is_cluster_unity_catalog_enabled():
            return
        try:
            TablePrivileges.from_environment_default(fqtn).apply()
        except Exception as error:
            logger.error(f"Failed to apply default table privileges on {fqtn}: {error}")

    def _ensure_store_table(self, table: str, fqtn: str, location: str) -> None:
        """Register an existing Delta location in the metastore when needed (EMR).

        Databricks may create the store first; EMR then sees non-empty S3 data
        without a catalog entry and ``saveAsTable`` fails with
        ``DELTA_CREATE_TABLE_WITH_NON_EMPTY_LOCATION``. Mirror ``DeltaLoader``:
        register the external table, then append via ``insertInto``.
        """
        if self.spark.catalog.tableExists(fqtn):
            return
        if not DeltaTable.isDeltaTable(self.spark, location):
            return
        logger.info(
            f"Delta data exists at {location} but {fqtn} is missing from the "
            "metastore. Registering external table from location."
        )
        self.spark.sql(
            f"CREATE TABLE IF NOT EXISTS `{DATABASE}`.`{table}` "
            f"USING DELTA LOCATION '{location}'"
        )

    @staticmethod
    def _project(record: dict, schema: StructType) -> dict:
        """Keep only schema fields, by name (missing -> None, extras dropped).

        Name-based (not positional) so the record shape can drift from the schema
        without silently mapping a value into the wrong column.
        """
        return {field.name: record.get(field.name) for field in schema.fields}
