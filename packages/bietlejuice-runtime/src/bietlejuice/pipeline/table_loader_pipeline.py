from abc import abstractmethod

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.spark_table_storage_format import SparkTableStorageFormat
from bietlejuice.base.udfs.udf_enum import UDFEnum
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import DatabricksConsumer
from bietlejuice.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.services.metastore_services.metastore_service_factory import (
    MetastoreServiceFactory,
)


class TableLoaderPipeline(AbstractPipeline):
    """
    Class to create a table in spark metastore from a specified query.
    """

    def __init__(
        self,
        database_name: str,
        table_name: str,
        database_location: str,
        layer: str,
        query: str,
        partitions: list = None,
        query_template_params: dict = None,
        target_database_name: str = None,
        target_database_location: str = None,
        spark_session_configs: dict = None,
        table_privileges: TablePrivileges = None,
    ):
        """
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
        :param table_privileges: TablePrivileges object to apply table privileges after loading the table
        """
        self.database_name = database_name
        self.table_name = table_name
        self.database_location = database_location
        self.layer = layer
        self.query = query
        self.query_template_params = query_template_params or {}
        self.target_database_name = target_database_name or database_name
        self.target_database_location = target_database_location or database_location
        self.partitions = partitions or []
        self.spark_session_configs = spark_session_configs or {}
        self.table_privileges = table_privileges

    def run(self):
        """
        Creates the table in spark metastore based in the query and according to the layer set
        """
        spark_client = SparkClient()

        databases_to_be_created = [self.target_database_name, self.database_name]

        spark_metastore_service = (
            MetastoreServiceFactory.create_loader_metastore_service(spark_client)
        )
        for database in databases_to_be_created:
            spark_metastore_service.create_database(database)

        for udf_identifier in self.spark_session_configs.get("udfs", []):
            self.register_udf(spark_client, udf_identifier)

        conn_config = {"db": self.database_name}
        databricks_consumer = DatabricksConsumer(conn_config, spark_client)

        df = databricks_consumer.get_data_from_query(
            self.query.format(**self.query_template_params)
        )

        format_options = SparkTableStorageFormat.get_storage(self.layer)

        self.load_and_register(df, format_options)

    @abstractmethod
    def load_and_register(self, df, format_options, **load_options):
        raise NotImplementedError()

    def _ensure_secondary_catalog_table(self, df, format_options):
        """Ensure the parquet/json table exists in the secondary catalog.

        On Databricks + Unity Catalog the table is saved via ``saveAsTable`` and
        ``SparkMetastoreLoader.update_metastore`` is skipped, so the external table
        is never created in Glue and partition registration silently no-ops. Mirror
        ``DeltaTableLoaderPipeline`` by syncing the table to the secondary catalog
        (Glue on Databricks, UC REST on EMR) before registering partitions. The sync
        is idempotent and runtime-aware; Delta is excluded by the format guard.
        """
        if not self._uses_glue_hive_partitions(format_options):
            return

        from bietlejuice.base.spark.catalog_strategy_resolver import (
            CatalogStrategyResolver,
        )
        from bietlejuice.services.schema_service import SchemaService

        table_schema = SchemaService.get_schema_from_dataframe(df)
        CatalogStrategyResolver.sync_to_secondary_catalog(
            database_name=self.target_database_name,
            table_name=self.table_name,
            table_location=self.target_database_location + self.table_name,
            table_schema=table_schema,
            partitions=self.partitions,
            format_str=format_options,
        )

    def _register_partitions_from_df(
        self,
        metastore_service,
        df,
        database_name,
        table_name,
        format_options,
    ):
        """Register hive-style partitions in Glue for parquet/json tables only."""
        if not self.partitions:
            return
        if not self._uses_glue_hive_partitions(format_options):
            return
        metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=table_name,
            partition_cols=self.partitions,
        )

    @staticmethod
    def _uses_glue_hive_partitions(format_options) -> bool:
        if not isinstance(format_options, str):
            return False
        return format_options.upper() in (
            SparkTableStorageFormat.PARQUET,
            SparkTableStorageFormat.JSON,
        )

    def register_udf(self, spark_client, udf_identifier):
        """
        Registers a function as a UDF into Spark session, setting the `udf_indentifier`
        as an available SQL function call. It uses the provided `udf_identifier` to
        retrieve the function from a Enum mapping.

        :param spark_client : Spark client object, whose session will be used.
        :type spark_client: SparkClient
        :param udf_identifier: a string representing the UDF identifier. Also used to
                  call the respective function inside SQL queries.
        :type udf_identifier: str
        """
        udf = UDFEnum.get_udf(udf_identifier=udf_identifier)
        if udf:
            spark_client.conn.udf.register(udf_identifier, udf)
