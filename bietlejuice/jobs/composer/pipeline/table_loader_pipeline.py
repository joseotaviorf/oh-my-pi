from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader, S3Loader
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.spark_services.spark_configurator_service import (
    SparkConfiguratorService,
)


class TableLoaderPipeline(AbstractPipeline):
    """
    Class to create a table in spark metastore from a specified query.
    """

    def __init__(
        self,
        database_name,
        table_name,
        database_location,
        layer,
        query,
        partitions=None,
        query_template_params=None,
        is_incremental=False,
        target_database_name=None,
        target_database_location=None,
        spark_params=None,
    ):
        """
        :param database_name: database name to create the enriched table
        :param table_name: table name
        :param database_location: database location in S3
        :param layer: stage of pipeline
        :param query: query for specified table
        :param partitions: list of columns to partition table
        :param query_template_params: dict of parameters to apply to query template, example: {'year':2020, 'month':1, 'day':1}
        :param is_incremental: if this table uses incremental load type
        """
        self.database_name = database_name
        self.table_name = table_name
        self.database_location = database_location
        self.layer = layer
        self.query = query
        self.query_template_params = query_template_params or {}
        self.is_incremental = is_incremental
        self.target_database_name = target_database_name or database_name
        self.target_database_location = target_database_location or database_location
        self.partitions = partitions or []
        self.spark_params = spark_params

    def run(self):
        """
        Creates the table in spark metastore based in the query and according to the layer set
        """
        spark_client = SparkClient()

        databases_to_be_created = [self.target_database_name, self.database_name]

        spark_metastore_service = SparkMetastoreService(spark_client)
        for database in databases_to_be_created:
            spark_metastore_service.create_database(database)

        if self.spark_params:
            spark_configurator_service = SparkConfiguratorService(
                spark_client, self.spark_params
            )
            spark_configurator_service.configure_spark_session()

        conn_config = {"db": self.database_name}
        databricks_consumer = DatabricksConsumer(conn_config, spark_client)

        df = databricks_consumer.get_data_from_query(
            self.query.format(**self.query_template_params)
        )

        format_options = SparkTableStorageFormat.get_storage(self.layer)
        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            format_options=format_options,
            s3_path=self.target_database_location + self.table_name,
            partitions=self.partitions,
            is_incremental=self.is_incremental,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=self.target_database_name,
            table_name=self.table_name,
            format_options=format_options,
            database_location=self.target_database_location,
            partitions=self.partitions,
        )

        if self.is_incremental:
            spark_metastore_service.create_new_partitions_from_df(
                df=df,
                database_name=self.target_database_name,
                table_name=self.table_name,
                partition_cols=self.partitions,
            )

            spark_metastore_service.refresh_table(
                self.target_database_name, self.table_name
            )
