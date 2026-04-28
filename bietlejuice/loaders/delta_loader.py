import re

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.base.spark.spark_table_property_helper import SparkTablePropertyHelper
from pyspark.sql import DataFrame
from pyspark.sql.utils import AnalysisException
from pyspark.sql.types import StructField, StructType
from py4j.protocol import Py4JJavaError
from delta.tables import DeltaTable


logger = QuintoAndarLogger("DeltaLoader")

_VALID_COLUMN_MAPPING_MODES = {"none", "name", "id"}

# Matches only safe SQL identifiers: letters, digits, underscores, and dots
# (dots are used for qualified names like schema.table). This pattern is used
# instead of a frozenset to allow static-analysis tools to recognise it as a
# sanitizer and avoid false-positive SQL-injection findings.
_SAFE_IDENTIFIER_RE = re.compile(r"^[a-zA-Z0-9_.]+$")


def _check_identifier_safety(value: str) -> None:
    """Raise ValueError if `value` is not a safe SQL identifier.

    Accepts snake_case names and qualified names (schema.table). Rejects any
    character that could break out of an identifier context in a SQL statement.
    """
    if not value or not _SAFE_IDENTIFIER_RE.match(value):
        raise ValueError(f"Invalid SQL identifier: {value!r}")


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
    ) -> None:
        """
        Load a DataFrame into a Delta table.

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
        _check_identifier_safety(table_name)
        database_name = table_name.split(".")[0]
        _check_identifier_safety(database_name)
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
        if not exists or not is_delta:
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

    @staticmethod
    def convert_schema_to_nullable(schema: StructField) -> StructField:
        return StructType(
            [StructField(field.name, field.dataType, True) for field in schema.fields]
        )

    def _convert_to_delta_table(self, table_name: str) -> None:
        """Convert a table to a Delta table"""
        _check_identifier_safety(table_name)
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
            _check_identifier_safety(table_name)
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
        join_condition = " AND ".join(
            [f"source.{col} = target.{col}" for col in merge_on]
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

    def vacuum_table(self, table_name: str, retention_hours: int) -> None:
        """Vacuum a Delta table"""
        _check_identifier_safety(table_name)

        # We shouldn't use RETAIN HOURS anymore
        # https://docs.databricks.com/aws/en/release-notes/whats-coming#behavioral-change-for-working-with-delta-table-history-and-vacuum
        SparkTablePropertyHelper.set_property(
            table_name,
            property_name="delta.deletedFileRetentionDuration",
            property_value=f"{retention_hours} hours",
            spark=self.spark,
        )

        command = f"VACUUM {table_name}"
        logger.info(
            f"Running vacuum with command {command}, and retention hours {retention_hours}"
        )
        self.spark.sql(command)
        logger.info(f"Vacuum successful for table {table_name}")

    def vacuum_lite_table(self, table_name: str, retention_hours: int) -> None:
        """Vacuum a Delta table in lite mode. Only available in Databricks Runtime 16.1 and above."""
        _check_identifier_safety(table_name)

        # We shouldn't use RETAIN HOURS anymore
        # https://docs.databricks.com/aws/en/release-notes/whats-coming#behavioral-change-for-working-with-delta-table-history-and-vacuum
        SparkTablePropertyHelper.set_property(
            table_name,
            property_name="delta.deletedFileRetentionDuration",
            property_value=f"{retention_hours} hours",
            spark=self.spark,
        )

        command = f"VACUUM {table_name} LITE"
        logger.info(
            f"Running vacuum lite with command {command}, and retention hours {retention_hours}"
        )
        self.spark.sql(command)
        logger.info(f"Vacuum lite successful for table {table_name}")

    def optimize_table(self, table_name: str, z_order_by: list = None) -> None:
        """Optimize a Delta table, optionally using ZORDER BY"""
        _check_identifier_safety(table_name)

        command = f"OPTIMIZE {table_name}"
        if z_order_by:
            command += f" ZORDER BY {','.join(z_order_by)}"
        logger.info(f"Running optimize with command {command}")
        self.spark.sql(command)
        logger.info(f"Optimize successful for table {table_name}")
