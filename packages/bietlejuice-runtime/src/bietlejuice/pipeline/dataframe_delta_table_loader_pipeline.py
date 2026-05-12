from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.base.spark.catalog_strategy_resolver import CatalogStrategyResolver
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.services.metastore_services.metastore_service_factory import (
    MetastoreServiceFactory,
)
from bietlejuice.services.schema_service import SchemaService

logger = QuintoAndarLogger("DataFrameDeltaTableLoaderPipeline")


class DataFrameDeltaTableLoaderPipeline(AbstractPipeline):
    """
    Pipeline class that accepts a dataframe directly instead of a query,
    but still applies permissions and other Delta table functionality.

    This class is useful when you already have a DataFrame constructed
    and want to load it as a Delta table with all the standard privileges
    and merge capabilities.
    """

    def __init__(
        self,
        database_name: str,
        table_name: str,
        database_location: str,
        layer: str,
        dataframe: DataFrame,
        partitions: list = None,
        target_database_name: str = None,
        target_database_location: str = None,
        spark_session_configs: dict = None,
        merge_schema: bool = True,
        merge_on: list = None,
        when_not_matched_insert_condition: str = None,
        when_matched_update_condition: str = None,
        when_matched_delete_condition: str = None,
        when_not_matched_by_source_delete_condition: str = None,
        when_matched_operation: dict = None,
        when_not_matched_operation: dict = None,
        table_privileges: TablePrivileges = None,
        spark=BaseSparkContext.spark,
    ):
        """
        Initialize the pipeline with a DataFrame instead of a query.

        By default, it will simply do a write operation of a Delta table.

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

        :param database_name: database name to create the enriched table
        :param table_name: table name
        :param database_location: database location in S3
        :param layer: stage of pipeline
        :param dataframe: DataFrame to be loaded into the Delta table
        :param partitions: list of columns to partition table
        :param target_database_name: target database name
        :param target_database_location: target database location in S3
        :param spark_session_configs: custom config parameters to be set in spark session
        :param merge_schema: whether to merge schema or not
        :param merge_on: list of columns to merge on
        :param when_not_matched_insert_condition: condition to insert when not matched
        :param when_matched_update_condition: condition to update when matched
        :param when_matched_delete_condition: condition to delete when matched
        :param when_not_matched_by_source_delete_condition: condition to delete from target when not matched by source
        :param when_matched_operation: Dictionary specifying columns and values to update on a match.
        :param when_not_matched_operation: Dictionary specifying columns and values to insert on no match.
        :param table_privileges: TablePrivileges object to apply table privileges after loading the table
        :param spark: Spark session to use
        """
        self.database_name = database_name
        self.table_name = table_name
        self.database_location = database_location
        self.layer = layer
        self.dataframe = dataframe
        self.target_database_name = target_database_name or database_name
        self.target_database_location = target_database_location or database_location
        self.partitions = partitions or []
        self.spark_session_configs = spark_session_configs or {}
        self.merge_schema = merge_schema
        self.merge_on = merge_on
        self.when_not_matched_insert_condition = when_not_matched_insert_condition
        self.when_matched_update_condition = when_matched_update_condition
        self.when_matched_delete_condition = when_matched_delete_condition
        self.when_not_matched_by_source_delete_condition = (
            when_not_matched_by_source_delete_condition
        )
        self.when_matched_operation = when_matched_operation
        self.when_not_matched_operation = when_not_matched_operation
        self.table_privileges = table_privileges
        self.spark = spark

    def run(self):
        """
        Creates the table in spark metastore from the provided DataFrame
        """
        spark_client = SparkClient()

        # Create databases if they don't exist
        databases_to_be_created = [self.target_database_name, self.database_name]
        spark_metastore_service = (
            MetastoreServiceFactory.create_loader_metastore_service(spark_client)
        )
        for database in databases_to_be_created:
            spark_metastore_service.create_database(database)

        # Register UDFs if specified
        for udf_identifier in self.spark_session_configs.get("udfs", []):
            self._register_udf(spark_client, udf_identifier)

        # Load the DataFrame using Delta loader
        self._load_and_register()

    def _load_and_register(self):
        """Load the DataFrame to Delta table and apply permissions"""
        spark_client = SparkClient()
        spark_metastore_service = (
            MetastoreServiceFactory.create_loader_metastore_service(spark_client)
        )
        delta_loader = DeltaLoader(spark=self.spark)

        s3_path = self.target_database_location + self.table_name
        full_table_name = f"{self.target_database_name}.{self.table_name}"

        logger.info(
            f"Loading DataFrame to Delta table {full_table_name} at path {s3_path}"
        )

        delta_loader.load_table(
            table_name=full_table_name,
            path=s3_path,
            source_df=self.dataframe,
            partition_by=self.partitions,
            merge_schema=self.merge_schema,
            merge_on=self.merge_on,
            when_not_matched_insert_condition=self.when_not_matched_insert_condition,
            when_matched_update_condition=self.when_matched_update_condition,
            when_matched_delete_condition=self.when_matched_delete_condition,
            when_not_matched_by_source_delete_condition=self.when_not_matched_by_source_delete_condition,
            when_matched_operation=self.when_matched_operation,
            when_not_matched_operation=self.when_not_matched_operation,
        )

        # Refresh the table in metastore
        spark_metastore_service.refresh_table(
            self.target_database_name, self.table_name
        )

        table_schema = SchemaService.get_schema_from_dataframe(self.dataframe)
        CatalogStrategyResolver.sync_to_secondary_catalog(
            database_name=self.target_database_name,
            table_name=self.table_name,
            table_location=s3_path,
            table_schema=table_schema,
            partitions=self.partitions,
            format_str="DELTA",
        )

        # Apply table privileges if specified and Unity Catalog is enabled
        if (
            self.table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            logger.info(f"Applying table privileges to {full_table_name}")
            self.table_privileges.apply()

    def _register_udf(self, spark_client, udf_identifier):
        """
        Registers a function as a UDF into Spark session, setting the `udf_identifier`
        as an available SQL function call. It uses the provided `udf_identifier` to
        retrieve the function from a Enum mapping.

        :param spark_client : Spark client object, whose session will be used.
        :type spark_client: SparkClient
        :param udf_identifier: a string representing the UDF identifier. Also used to
                  call the respective function inside SQL queries.
        :type udf_identifier: str
        """
        from bietlejuice.base.udfs.udf_enum import UDFEnum

        udf = UDFEnum.get_udf(udf_identifier=udf_identifier)
        if udf:
            spark_client.conn.udf.register(udf_identifier, udf)
