from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark.base_spark import BaseSparkContext
from pyspark.sql import DataFrame
from pyspark.sql.utils import AnalysisException
from py4j.protocol import Py4JJavaError
from delta.tables import DeltaTable


logger = QuintoAndarLogger("DeltaLoader")


class DeltaLoader:
    """Class for loading data into a Delta table"""

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
        """
        database_name = table_name.split(".")[0].replace("`", "")
        BaseSparkContext.spark.sql(f"CREATE DATABASE IF NOT EXISTS `{database_name}`")

        exists = BaseSparkContext.spark.catalog.tableExists(table_name)
        is_delta = DeltaTable.isDeltaTable(BaseSparkContext.spark, path)
        if exists and not is_delta:
            logger.info(f"Path {path} is not a Delta Table. Running conversion.")
            self._convert_to_delta_table(table_name)
        if not exists or not is_delta:
            logger.info(
                f"Table {table_name} does not exist. Creating a new empty table {table_name} on location."
            )
            self._create_empty_table(
                table_name, path, source_df, partition_by, replace_if_exists=False
            )

        if not merge_on:
            logger.info(f"Writing to table {table_name} on path {path}.")
            self._write_to_table(
                table_name, path, source_df, partition_by, merge_schema
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
            )
        logger.info(f"Load of table {table_name} completed successfully.")

    def _create_empty_table(
        self,
        table_name: str,
        path: str,
        source_df: DataFrame,
        partition_by: list = None,
        replace_if_exists: bool = False,
    ) -> DeltaTable:
        """Create an empty Delta table"""
        if replace_if_exists:
            builder = DeltaTable.createOrReplace(BaseSparkContext.spark)
        else:
            builder = DeltaTable.createIfNotExists(BaseSparkContext.spark)
        builder = builder.tableName(table_name)
        builder = builder.addColumns(source_df.schema)
        if partition_by:
            builder = builder.partitionedBy(*partition_by)
        builder = builder.location(path)
        return builder.execute()

    def _convert_to_delta_table(self, table_name: str) -> None:
        """Convert a table to a Delta table"""
        try:
            BaseSparkContext.spark.sql(f"CONVERT TO DELTA {table_name}")
            logger.info(f"Table {table_name} converted to Delta format.")
        except Py4JJavaError as e:
            error_class = e.java_exception.getClass().getName()
            # This error happens when the table exists in the Metastore and is parquet, but there is no data in it.
            # In this case, we can simply drop the table.
            if error_class != "java.io.FileNotFoundException":
                raise e
            logger.info(f"Table {table_name} exists, but has no data. Dropping it.")
            BaseSparkContext.spark.sql(f"DROP TABLE {table_name}")
        except AnalysisException as e:
            error_class = e.getErrorClass()
            # This error happens when the the table is a Delta table, but the Delta log was deleted.
            # In this case, we can simply drop the table.
            if error_class != "DELTA_TABLE_NOT_FOUND":
                raise e
            logger.info(
                f"Delta log or table {table_name} was deleted. Dropping from Metastore so it can be recreated."
            )
            BaseSparkContext.spark.sql(f"DROP TABLE {table_name}")

    def _write_to_table(
        self,
        table_name: str,
        path: str,
        source_df: DataFrame,
        partition_by: list = None,
        merge_schema: bool = True,
    ) -> None:
        """Write a DataFrame to a Delta table"""
        source_df.write.format("delta").option("mergeSchema", merge_schema).mode(
            "overwrite"
        ).saveAsTable(table_name, path=path, partitionBy=partition_by)

    def _merge_to_table(
        self,
        table_name: str,
        source_df: DataFrame,
        merge_on: list,
        when_not_matched_insert_condition: str = None,
        when_matched_update_condition: str = None,
        when_matched_delete_condition: str = None,
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
        """

        # Necessary for schema evolution
        BaseSparkContext.spark.conf.set(
            "spark.databricks.delta.schema.autoMerge.enabled", "true"
        )

        target_table = DeltaTable.forName(BaseSparkContext.spark, table_name)
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

        merge_builder.whenMatchedUpdateAll(
            condition=when_matched_update_condition
        ).whenNotMatchedInsertAll(condition=when_not_matched_insert_condition).execute()

    def vacuum_table(self, table_name: str, retention_hours: int) -> None:
        """Vacuum a Delta table"""

        spark = BaseSparkContext.spark
        command = f"VACUUM {table_name} RETAIN {retention_hours} HOURS"
        logger.info(f"Running vacuum with command {command}")
        spark.sql(command)
        logger.info(f"Vacuum successful for table {table_name}")

    def optimize_table(self, table_name: str, z_order_by: list = None) -> None:
        """Optimize a Delta table, optionally using ZORDER BY"""

        spark = BaseSparkContext.spark
        command = f"OPTIMIZE {table_name}"
        if z_order_by:
            command += f" ZORDER BY {','.join(z_order_by)}"
        logger.info(f"Running optimize with command {command}")
        spark.sql(command)
        logger.info(f"Optimize successful for table {table_name}")
