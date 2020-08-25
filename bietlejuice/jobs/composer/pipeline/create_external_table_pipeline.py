from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)


class CreateExternalTablePipeline(AbstractPipeline):
    """
    Class to create an external table in Athena metastore
    """

    def __init__(
        self,
        athena_query_result_location,
        athena_database_name,
        table_name,
        database_location,
        format_options,
        spark_database_name,
        query_template_params=None,
        partitions=None,
        is_incremental=False,
    ):
        """
        :param athena_query_result_location: athena query results location in S3
        :param athena_database_name: database name to create table
        :param table_name: table name to create
        :param database_location: database location in S3
        :param format_options: file in S3
        :param spark_database_name: database name in spark metastore to get table schema
        :param partitions: list of columns to partition table
        :param is_incremental: if this table uses incremental load type
        :param query_template_params: dict of parameters to apply to query template, example: {'year':2020, 'month':1, 'day':1}
        """
        self.athena_query_result_location = athena_query_result_location
        self.athena_database_name = athena_database_name
        self.table_name = table_name
        self.database_location = database_location
        self.format_options = format_options
        self.spark_database_name = spark_database_name
        self.is_incremental = is_incremental
        self.partitions = partitions or []

    def run(self):
        """
        Execute logic to create the external table in Athena
        """
        athena_client = AthenaClient(self.athena_query_result_location)
        athena_metastore_service = AthenaMetastoreService(athena_client)
        athena_metastore_service.create_database(self.athena_database_name)

        spark_metastore_service = SparkMetastoreService(SparkClient())
        table_schema = spark_metastore_service.get_table_schema(
            self.spark_database_name, self.table_name
        )

        if not self.is_incremental:
            athena_metastore_service.drop_table(
                self.athena_database_name, self.table_name
            )

        athena_metastore_service.create_external_table(
            database_name=self.athena_database_name,
            table_name=self.table_name,
            table_location=self.database_location + self.table_name,
            table_schema=table_schema,
            partition_cols=self.partitions,
            format_options=self.format_options,
        )

        if self.is_incremental:
            conn_config = {"db": self.spark_database_name}
            databricks_consumer = DatabricksConsumer(conn_config, SparkClient())

            df = databricks_consumer.get_data_from_table(self.table_name)

            athena_metastore_service.create_new_partitions_from_df(
                database_name=self.athena_database_name,
                table_name=self.table_name,
                partition_cols=self.partitions,
                df=df,
            )
