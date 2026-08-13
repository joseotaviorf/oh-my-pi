import re

from delta.tables import DeltaTable
from py4j.protocol import Py4JJavaError
from pyspark.sql import DataFrame
from pyspark.sql.types import StructField, StructType
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.base.spark.schema_alignment import align_source_to_target
from bietlejuice.base.spark.spark_table_property_helper import SparkTablePropertyHelper

logger = QuintoAndarLogger("DeltaLoader")

_VALID_COLUMN_MAPPING_MODES = {"none", "name", "id"}

# Delta raises this error class when VACUUM LITE cannot see every removable file
# (log pruned, or no full VACUUM baseline inside the log retention window).
_VACUUM_LITE_NOT_APPLICABLE_ERROR_CLASS = "DELTA_CANNOT_VACUUM_LITE"

# Delta records "already cleaned up to this commit version" in this file. A *full* VACUUM
# persists a null value into it (VacuumCommand.gc computes the version only for LITE runs,
# then persists unconditionally), which permanently disqualifies a log-truncated table from
# LITE. We rewrite it after a successful full vacuum so the next run can use LITE again.
# Byte format captured from a real successful `VACUUM ... LITE` on delta-spark 3.3.1:
#   b'{"latestCommitVersionOutsideOfRetentionWindow":5}\n'
# The trailing newline comes from LogStore.write(path, Iterator.single(json)).
_LAST_VACUUM_INFO_FILE_NAME = "_last_vacuum_info"
_DELTA_LOG_DIR_NAME = "_delta_log"
_DELTA_COMMIT_FILE_RE = re.compile(r"^(\d{20})\.json$")

# Matches only safe SQL identifiers: letters, digits, underscores, and dots
# (dots are used for qualified names like schema.table). This pattern is used
# instead of a frozenset to allow static-analysis tools to recognise it as a
# sanitizer and avoid false-positive SQL-injection findings.
_SAFE_IDENTIFIER_RE = re.compile(r"^[a-zA-Z0-9_.]+$")
_SAFE_IDENTIFIER_SEGMENT_RE = re.compile(r"^[a-zA-Z0-9_]+$")


def _check_identifier_safety(value: str) -> str:
    """Return `value` if it is a safe SQL identifier, else raise ValueError.

    Accepts snake_case names and qualified names (schema.table). Rejects any
    character that could break out of an identifier context in a SQL statement.

    Returning the validated value (rather than being void) is intentional: SAST
    tools break the taint chain only when the value used in SQL is the *return*
    of a validation function, not when a void guard is called before the
    original variable is reused.
    """
    if not value or not _SAFE_IDENTIFIER_RE.match(value):
        raise ValueError(f"Invalid SQL identifier: {value!r}")
    return value


def _quote_sql_table_name(qualified_name: str) -> str:
    """Return a backtick-quoted ``db`.`table`` name for Delta SQL commands.

    Reserved words (e.g. ``location``) must be quoted when followed by ``WHERE``
    in ``OPTIMIZE`` statements on Spark SQL parsers (EMR Delta OSS).
    """
    qualified_name = _check_identifier_safety(qualified_name)
    parts = qualified_name.split(".")
    if not parts:
        raise ValueError(f"Invalid SQL identifier: {qualified_name!r}")
    quoted_parts = []
    for part in parts:
        if not part or not _SAFE_IDENTIFIER_SEGMENT_RE.match(part):
            raise ValueError(f"Invalid SQL identifier segment: {part!r}")
        quoted_parts.append(f"`{part}`")
    return ".".join(quoted_parts)


class DeltaLoader:
    """Class for loading data into a Delta table"""

    def __init__(self, spark=BaseSparkContext.spark) -> None:
        self.spark = spark

    def load_table(
        self,
        table_name: str,
        path: str,
        source_df: DataFrame,
        partition_by: list = None,
        merge_schema: bool = True,
        merge_on: list = None,
        when_not_matched_insert_condition: str = None,
        when_matched_update_condition: str = None,
        when_matched_delete_condition: str = None,
        when_not_matched_by_source_delete_condition: str = None,
        when_matched_operation: dict = None,
        when_not_matched_operation: dict = None,
        column_mapping_mode: str = None,
    ) -> DataFrame:
        """
        Load a DataFrame into a Delta table.

        Returns the DataFrame actually written — identical to ``source_df``
        unless the target already existed, in which case ``string`` columns
        registered as Glue-fragile timestamp/date are cast to the target's
        real type first. Callers that derive a schema for catalog sync
        (e.g. ``SchemaService.get_schema_from_dataframe``) must use this
        return value, not their original ``source_df``, or the secondary
        catalog registers the pre-alignment type.

        By default, it will simply do a write operation.

        However, if "merge_on" is specified, it will perform a merge operation, using the list of columns specified as merge keys.
        If nothing else besides this column is specified, it will update when matched, and insert when not matched (simple upsert).

        You can change this behavior by setting:
        - when_not_matched_insert_condition: it will only insert when this specified condition is true
        - when_matched_update_condition: it will only update when this specified condition is true. You can refer to the columns
        in the source dataframe as source.<column_name>, and the columns in the target table as target.<column_name>.
        - when_matched_delete_condition: it will add an operation to delete, but only if this condition is true. Again, source and
        target dataframe columns can be referred to respectively as source.<column_name> and target.<column_name>
        - when_not_matched_by_source_delete_condition: it will delete rows from target that don't exist in source when this condition is true.
        You can refer to target columns as target.<column_name>. Useful for full-load scenarios where missing records should be removed.
        - when_matched_operation: Specifies the columns to update on a match, along with their values. This should be a dictionary,
        where keys represent columns to update and values specify the new values. You can use source.<column_name> or target.<column_name> to differentiate between the source and target data.
        - when_not_matched_operation: Specifies the columns and values to insert when there is no match. This should also be a dictionary,
        where keys are the columns to insert, and values are the data to be inserted. Again, source.<column_name> or target.<column_name> can be used to clarify data origin.
        """
        table_name = _check_identifier_safety(table_name)
        database_name = _check_identifier_safety(table_name.split(".")[0])
        self.spark.sql(f"CREATE DATABASE IF NOT EXISTS `{database_name}`")

        exists = self.spark.catalog.tableExists(table_name)
        try:
            DeltaTable.forName(self.spark, table_name)
            is_delta = True
        except AnalysisException:
            is_delta = False

        if exists and not is_delta:
            logger.info(f"Path {path} is not a Delta Table. Running conversion.")
            self._convert_to_delta_table(table_name)
            exists = self.spark.catalog.tableExists(table_name)
            if exists:
                try:
                    DeltaTable.forName(self.spark, table_name)
                    is_delta = True
                except AnalysisException:
                    is_delta = False
        if not exists or not is_delta:
            if path and self._delta_exists_at_path(path):
                logger.info(
                    f"Delta data exists at {path} but {table_name} is missing from or "
                    "invalid in the metastore. Registering external table from location."
                )
                self._register_delta_table_at_path(table_name, path)
                exists = True
                is_delta = True
            else:
                logger.info(
                    f"Table {table_name} does not exist. Creating a new empty table {table_name} on location."
                )
                self._create_empty_table(
                    table_name,
                    path,
                    source_df,
                    partition_by,
                    replace_if_exists=False,
                    column_mapping_mode=column_mapping_mode,
                )

        if exists and is_delta:
            # Raw JSON tables register timestamp/date/decimal as string on Glue
            # (the JsonSerDe cannot parse ISO-8601 and ClassCasts String to
            # HiveDecimal), while this target already holds the real type. Merge
            # aborts on the mismatch and overwrite would degrade the target's
            # type, so cast to what the table declares — for a decimal, at its
            # declared precision. No-op when the table was just created from
            # source_df.
            source_df = align_source_to_target(self.spark, source_df, table_name)

        if not merge_on:
            logger.info(f"Writing to table {table_name} on path {path}.")
            self._write_to_table(
                table_name,
                source_df,
                partition_by,
                merge_schema,
                column_mapping_mode=column_mapping_mode,
            )
        else:
            logger.info(f"Merging to table {table_name}.")
            self._merge_to_table(
                table_name,
                source_df,
                merge_on,
                when_not_matched_insert_condition,
                when_matched_update_condition,
                when_matched_delete_condition,
                when_not_matched_by_source_delete_condition,
                when_matched_operation,
                when_not_matched_operation,
            )
        logger.info(f"Load of table {table_name} completed successfully.")
        return source_df

    def _create_empty_table(
        self,
        table_name: str,
        path: str,
        source_df: DataFrame,
        partition_by: list = None,
        replace_if_exists: bool = False,
        column_mapping_mode: str = None,
    ) -> DeltaTable:
        """Create an empty Delta table"""
        if replace_if_exists:
            builder = DeltaTable.createOrReplace(self.spark)
        else:
            builder = DeltaTable.createIfNotExists(self.spark)
        builder = builder.tableName(table_name)
        if column_mapping_mode:
            builder = builder.property("delta.columnMapping.mode", column_mapping_mode)
        schema = self.convert_schema_to_nullable(source_df.schema)
        builder = builder.addColumns(schema)
        if partition_by:
            builder = builder.partitionedBy(*partition_by)
        builder = builder.location(path)
        return builder.execute()

    def _delta_exists_at_path(self, path: str) -> bool:
        """True when ``path`` already contains a Delta transaction log."""
        if not path:
            return False
        return DeltaTable.isDeltaTable(self.spark, path)

    def _register_delta_table_at_path(self, table_name: str, path: str) -> None:
        """Register existing Delta files in the metastore without rewriting schema."""
        quoted_table = _quote_sql_table_name(table_name)
        self.spark.sql(
            f"CREATE TABLE IF NOT EXISTS {quoted_table} USING DELTA LOCATION '{path}'"
        )

    @staticmethod
    def convert_schema_to_nullable(schema: StructField) -> StructField:
        return StructType(
            [StructField(field.name, field.dataType, True) for field in schema.fields]
        )

    def _convert_to_delta_table(self, table_name: str) -> None:
        """Convert a table to a Delta table"""
        table_name = _check_identifier_safety(table_name)
        try:
            self.spark.sql(f"CONVERT TO DELTA {table_name}")
            logger.info(f"Table {table_name} converted to Delta format.")
        except Py4JJavaError as e:
            error_class = e.java_exception.getClass().getName()
            # This error happens when the table exists in the Metastore and is parquet, but there is no data in it.
            # In this case, we can simply drop the table.
            if error_class != "java.io.FileNotFoundException":
                raise e
            logger.info(f"Table {table_name} exists, but has no data. Dropping it.")
            self.spark.sql(f"DROP TABLE {table_name}")
        except AnalysisException as e:
            error_class = e.getErrorClass()
            # These errors happen, respectively:
            # - When the table is Delta but the log was deleted
            # - When the table is parquet and partitioned but is empty
            # In these cases, we can simply drop the table for it to be recreated by the next method.
            if error_class not in (
                "DELTA_TABLE_NOT_FOUND",
                "DELTA_CONVERSION_NO_PARTITION_FOUND",
            ):
                raise e
            logger.info(
                f"Delta log or table {table_name} was deleted. Dropping from Metastore so it can be recreated."
            )
            self.spark.sql(f"DROP TABLE {table_name}")

    def _write_to_table(
        self,
        table_name: str,
        source_df: DataFrame,
        partition_by: list = None,
        merge_schema: bool = True,
        column_mapping_mode: str = None,
    ) -> None:
        """Write a DataFrame to a Delta table"""
        # Force partitioned tables to use mergeSchema. DBR 16.4+ doesn't allow overwriteSchema in this case
        if partition_by:
            merge_schema = True

        if column_mapping_mode:
            if column_mapping_mode not in _VALID_COLUMN_MAPPING_MODES:
                raise ValueError(
                    f"Invalid column_mapping_mode: {column_mapping_mode!r}"
                )
            table_name = _check_identifier_safety(table_name)
            self.spark.sql(
                f"ALTER TABLE {table_name} SET TBLPROPERTIES "
                f"('delta.columnMapping.mode' = '{column_mapping_mode}')"
            )

        writer = (
            source_df.write.format("delta")
            .option("mergeSchema", merge_schema)
            .option("overwriteSchema", not merge_schema)
        )
        writer.mode("overwrite").saveAsTable(table_name, partitionBy=partition_by)

    def _merge_to_table(
        self,
        table_name: str,
        source_df: DataFrame,
        merge_on: list,
        when_not_matched_insert_condition: str = None,
        when_matched_update_condition: str = None,
        when_matched_delete_condition: str = None,
        when_not_matched_by_source_delete_condition: str = None,
        when_matched_operation: dict = None,
        when_not_matched_operation: dict = None,
    ) -> None:
        """
        Merge a source dataframe to a Delta table, using the list of columns in "merge_on" as merge keys.
        By default, it will update when matched, and insert when not matched (simple upsert).

        You can change this behavior by setting:
        - when_not_matched_insert_condition: it will only insert when this specified condition is true
        - when_matched_update_condition: it will only update when this specified condition is true. You can refer to the columns
        in the source dataframe as source.<column_name>, and the columns in the target table as target.<column_name>.
        - when_matched_delete_condition: it will add an operation to delete, but only if this condition is true. Again, source and
        target dataframe columns can be referred to respectively as source.<column_name> and target.<column_name>
        - when_not_matched_by_source_delete_condition: it will delete rows from target that don't exist in source when this condition is true.
        You can refer to target columns as target.<column_name>. Useful for full-load scenarios where missing records should be removed.
        - when_matched_operation: Specifies the columns to update on a match, along with their values. This should be a dictionary,
        where keys represent columns to update and values specify the new values. You can use source.<column_name> or target.<column_name> to differentiate between the source and target data.
        - when_not_matched_operation: Specifies the columns and values to insert when there is no match. This should also be a dictionary,
        where keys are the columns to insert, and values are the data to be inserted. Again, source.<column_name> or target.<column_name> can be used to clarify data origin.
        """

        # Necessary for schema evolution
        self.spark.conf.set("spark.databricks.delta.schema.autoMerge.enabled", "true")

        target_table = DeltaTable.forName(self.spark, table_name)
        merge_keys = [_check_identifier_safety(col) for col in merge_on]
        join_condition = " AND ".join(
            [f"source.{col} = target.{col}" for col in merge_keys]
        )
        merge_builder = target_table.alias("target").merge(
            source_df.alias("source"), join_condition
        )
        if when_matched_delete_condition:
            merge_builder = merge_builder.whenMatchedDelete(
                condition=when_matched_delete_condition
            )

        if when_matched_operation:
            merge_builder = merge_builder.whenMatchedUpdate(
                condition=when_matched_update_condition, set=when_matched_operation
            )
        else:
            merge_builder = merge_builder.whenMatchedUpdateAll(
                condition=when_matched_update_condition
            )

        if when_not_matched_operation:
            merge_builder = merge_builder.whenNotMatchedInsert(
                condition=when_not_matched_insert_condition,
                values=when_not_matched_operation,
            )
        else:
            merge_builder = merge_builder.whenNotMatchedInsertAll(
                condition=when_not_matched_insert_condition
            )

        if when_not_matched_by_source_delete_condition:
            merge_builder = merge_builder.whenNotMatchedBySourceDelete(
                condition=when_not_matched_by_source_delete_condition
            )

        merge_builder.execute()

    def _run_full_vacuum(self, table_name: str, retention_hours: int) -> None:
        quoted_table = _quote_sql_table_name(table_name)
        command = f"VACUUM {quoted_table}"
        logger.info(
            f"Running vacuum with command {command}, and retention hours {retention_hours}"
        )
        self.spark.sql(command)
        logger.info(f"Vacuum successful for table {table_name}")

    def _delta_log_dir(self, table_name: str) -> str:
        """Return the ``_delta_log`` directory URI for ``table_name``.

        Resolved via ``DESCRIBE DETAIL`` rather than a config-derived path so it works for
        managed and external tables, on both the Databricks and Glue/Hive catalogs.
        """
        quoted_table = _quote_sql_table_name(table_name)
        location = (
            self.spark.sql(f"DESCRIBE DETAIL {quoted_table}")
            .select("location")
            .first()[0]
        )
        return f"{location.rstrip('/')}/{_DELTA_LOG_DIR_NAME}"

    def _persist_vacuum_lite_watermark(self, table_name: str) -> None:
        """Rewrite ``_last_vacuum_info`` so the *next* run is eligible for VACUUM LITE.

        A full vacuum makes Delta persist a null watermark, which permanently disqualifies a
        log-truncated table from LITE (``DELTA_CANNOT_VACUUM_LITE``). The full vacuum that
        just completed listed the whole table prefix and deleted everything eligible, so
        declaring "already cleaned up to <earliest retained commit>" is true.

        The earliest retained commit is the most conservative legal value: LITE's gate needs
        ``watermark >= earliestCommitVersion``, and a lower watermark only widens the commit
        range the next LITE scans, so it can discover more tombstones but never fewer.

        Best-effort by design. The vacuum has already succeeded when this runs, so any
        failure here is logged and swallowed: it only costs the next run a fallback.
        """
        try:
            log_dir = self._delta_log_dir(table_name)
            jvm = self.spark._jvm
            hadoop_conf = self.spark._jsc.hadoopConfiguration()
            log_path = jvm.org.apache.hadoop.fs.Path(log_dir)
            fs = log_path.getFileSystem(hadoop_conf)

            versions = []
            for status in fs.listStatus(log_path):
                match = _DELTA_COMMIT_FILE_RE.match(status.getPath().getName())
                if match:
                    versions.append(int(match.group(1)))
            if not versions:
                logger.warning(
                    f"No Delta commit files found under {log_dir}; skipping vacuum lite "
                    f"watermark for table {table_name}."
                )
                return

            earliest_version = min(versions)
            payload = (
                '{"latestCommitVersionOutsideOfRetentionWindow":'
                f"{earliest_version}"
                "}\n"
            )
            out_path = jvm.org.apache.hadoop.fs.Path(
                f"{log_dir}/{_LAST_VACUUM_INFO_FILE_NAME}"
            )
            stream = fs.create(out_path, True)
            try:
                stream.write(bytearray(payload.encode("utf-8")))
            finally:
                stream.close()

            logger.info(
                f"Persisted vacuum lite watermark {earliest_version} for table "
                f"{table_name}; next run should use VACUUM LITE."
            )
        except Exception as error:  # noqa: BLE001 - optimisation only, never fail the vacuum
            reason = str(error)[:500].replace("\n", " | ")
            logger.warning(
                f"Could not persist vacuum lite watermark for table {table_name} "
                f"({type(error).__name__}: {reason}); the next run will fall back to full "
                f"vacuum again."
            )

    def vacuum_table(self, table_name: str, retention_hours: int) -> None:
        """Vacuum a Delta table"""
        table_name = _check_identifier_safety(table_name)

        # We shouldn't use RETAIN HOURS anymore
        # https://docs.databricks.com/aws/en/release-notes/whats-coming#behavioral-change-for-working-with-delta-table-history-and-vacuum
        SparkTablePropertyHelper.set_property(
            table_name,
            property_name="delta.deletedFileRetentionDuration",
            property_value=f"{retention_hours} hours",
            spark=self.spark,
        )
        self._run_full_vacuum(table_name, retention_hours)

    def vacuum_lite_table(
        self,
        table_name: str,
        retention_hours: int,
        bootstrap_watermark: bool = False,
    ) -> None:
        """Vacuum a Delta table in lite mode (Delta 3.3+ / DBR 16.1+).

        Falls back to a full vacuum whenever the LITE statement fails: older runtimes
        cannot parse it at all, and Delta raises
        ``DELTA_CANNOT_VACUUM_LITE`` when the transaction log cannot back a LITE run.

        When ``bootstrap_watermark`` is set, a successful fallback also rewrites the
        ``_last_vacuum_info`` watermark that the full vacuum just nulled out, so the next
        run is eligible for LITE instead of falling back forever.
        """
        table_name = _check_identifier_safety(table_name)

        # We shouldn't use RETAIN HOURS anymore
        # https://docs.databricks.com/aws/en/release-notes/whats-coming#behavioral-change-for-working-with-delta-table-history-and-vacuum
        SparkTablePropertyHelper.set_property(
            table_name,
            property_name="delta.deletedFileRetentionDuration",
            property_value=f"{retention_hours} hours",
            spark=self.spark,
        )

        quoted_table = _quote_sql_table_name(table_name)
        command = f"VACUUM {quoted_table} LITE"
        logger.info(
            f"Running vacuum lite with command {command}, and retention hours {retention_hours}"
        )
        try:
            self.spark.sql(command)
        except Exception as error:  # noqa: BLE001 - see fallback rationale below
            reason = str(error)[:500].replace("\n", " | ")
            logger.warning(
                f"Vacuum lite failed for table {table_name} "
                f"({type(error).__name__}: {reason}); falling back to full vacuum. "
                f"Expected on runtimes older than Delta 3.3 (DBR < 16.1), which cannot "
                f"parse VACUUM ... LITE, and when Delta raises "
                f"{_VACUUM_LITE_NOT_APPLICABLE_ERROR_CLASS}."
            )
            self._run_full_vacuum(table_name, retention_hours)
            if bootstrap_watermark:
                self._persist_vacuum_lite_watermark(table_name)
            return
        logger.info(f"Vacuum lite successful for table {table_name}")

    def optimize_table(
        self,
        table_name: str,
        z_order_by: list = None,
        where_predicate: str = None,
    ) -> None:
        """Optimize a Delta table, optionally restricted by a partition predicate and/or ZORDER BY.

        The ``where_predicate`` must reference partition columns only and is the
        responsibility of the caller to construct safely (do not interpolate
        user input). Delta SQL grammar: ``OPTIMIZE table [WHERE pred] [ZORDER BY (...)]``.
        """
        table_name = _check_identifier_safety(table_name)
        quoted_table = _quote_sql_table_name(table_name)

        command = f"OPTIMIZE {quoted_table}"
        if where_predicate:
            command += f" WHERE {where_predicate}"
        if z_order_by:
            z_cols = [_check_identifier_safety(c) for c in z_order_by]
            command += f" ZORDER BY {','.join(z_cols)}"
        logger.info(f"Running optimize with command {command}")
        self.spark.sql(command)
        logger.info(f"Optimize successful for table {table_name}")
