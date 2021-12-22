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

        athena_metastore_service.drop_table(self.athena_database_name, self.table_name)

        athena_metastore_service.create_external_table(
            database_name=self.athena_database_name,
            table_name=self.table_name,
            table_location=self.database_location + self.table_name,
            table_schema=table_schema,
            partition_cols=self.partitions,
            format_options=self.format_options,
        )

        # TODO:  Map other points where is_incremental instead of partitions is determining if a msck repair table happens
        if self.partitions:
            athena_metastore_service.repair_table_partitions(
                self.athena_database_name, self.table_name
            )
