from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.pipeline.table_loader_pipeline import TableLoaderPipeline
from bietlejuice.services.metastore_services.spark_metastore_service import (
    SparkMetastoreService,
)
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("DeltaTableLoaderPipeline")


class DeltaTableLoaderPipeline(TableLoaderPipeline):
    def __init__(
        self,
        database_name,
        table_name,
        database_location,
        layer,
        query,
        partitions=None,
        query_template_params=None,
        target_database_name=None,
        target_database_location=None,
        spark_session_configs=None,
        merge_schema=True,
        merge_on: list = None,
        when_not_matched_insert_condition: str = None,
        when_matched_update_condition: str = None,
        when_matched_delete_condition: str = None,
        when_matched_operation: dict = None,
        when_not_matched_operation: dict = None,
        table_privileges: TablePrivileges = None,
        spark=BaseSparkContext.spark,
    ):
        """
        By default, it will simply do a write operation of a Delta table.

        However, if "merge_on" is specified, it will perform a merge operation, using the list of columns specified as merge keys.
        If nothing else besides this column is specified, it will update when matched, and insert when not matched (simple upsert).

        You can change this behavior by setting:
        - when_not_matched_insert_condition: it will only insert when this specified condition is true
        - when_matched_update_condition: it will only update when this specified condition is true. You can refer to the columns
        in the source dataframe as source.<column_name>, and the columns in the target table as target.<column_name>.
        - when_matched_delete_condition: it will add an operation to delete, but only if this condition is true. Again, source and
        target dataframe columns can be referred to respectively as source.<column_name> and target.<column_name>

        :param database_name: database name to create the enriched table
        :param table_name: table name
        :param database_location: database location in S3
        :param layer: stage of pipeline
        :param query: query for specified table
        :param partitions: list of columns to partition table
        :param query_template_params: dict of parameters to apply to query template, example: {'year':2020, 'month':1, 'day':1}
        :param target_database_name: target database name
        :param target_database_location: target database location in S3
        :param spark_session_configs: custom config parameters to be set in spark session
        :param merge_schema: whether to merge schema or not
        :param merge_on: list of columns to merge on
        :param when_not_matched_insert_condition: condition to insert when not matched
        :param when_matched_update_condition: condition to update when matched
        :param when_matched_delete_condition: condition to delete when matched
        :param when_matched_operation: Dictionary specifying columns and values to update on a match.
        :param when_not_matched_operation: Dictionary specifying columns and values to insert on no match.
        """
        super().__init__(
            database_name=database_name,
            table_name=table_name,
            database_location=database_location,
            layer=layer,
            query=query,
            partitions=partitions,
            query_template_params=query_template_params,
            target_database_name=target_database_name,
            target_database_location=target_database_location,
            spark_session_configs=spark_session_configs,
            table_privileges=table_privileges,
        )
        self.merge_schema = merge_schema
        self.merge_on = merge_on
        self.when_not_matched_insert_condition = when_not_matched_insert_condition
        self.when_matched_update_condition = when_matched_update_condition
        self.when_matched_delete_condition = when_matched_delete_condition
        self.when_matched_operation = when_matched_operation
        self.when_not_matched_operation = when_not_matched_operation
        self.spark = spark

    def load_and_register(self, df, format_options):
        spark_client = SparkClient()
        spark_metastore_service = SparkMetastoreService(spark_client)
        delta_loader = DeltaLoader(spark=self.spark)

        s3_path = self.target_database_location + self.table_name
        full_table_name = f"{self.target_database_name}.{self.table_name}"

        logger.info(
            f"Default format for layer {self.layer} is {format_options}. However, {full_table_name} will be loaded as Delta."
        )

        delta_loader.load_table(
            table_name=full_table_name,
            path=s3_path,
            source_df=df,
            partition_by=self.partitions,
            merge_schema=self.merge_schema,
            merge_on=self.merge_on,
            when_not_matched_insert_condition=self.when_not_matched_insert_condition,
            when_matched_update_condition=self.when_matched_update_condition,
            when_matched_delete_condition=self.when_matched_delete_condition,
            when_matched_operation=self.when_matched_operation,
            when_not_matched_operation=self.when_not_matched_operation,
        )

        spark_metastore_service.refresh_table(
            self.target_database_name, self.table_name
        )

        if (
            self.table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            self.table_privileges.apply()
