from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader, S3Loader
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


class TableLoaderPipeline(AbstractPipeline):
    """
    Class to create a table in spark metastore from a specified query.
    """

    def __init__(self, database_name, table_name, database_location, layer, query):
        """
        :param database_name: database name to create the enriched table
        :param table_name: table name
        :param database_location: database location in S3
        :param query: query for specified table
        """
        self.database_name = database_name
        self.table_name = table_name
        self.database_location = database_location
        self.layer = layer
        self.query = query

    def run(self):
        """
        Creates the table in spark metastore based in the query and according to the layer set
        """
        spark_client = SparkClient()
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(self.database_name)

        conn_config = {"db": self.database_name}
        databricks_consumer = DatabricksConsumer(conn_config, spark_client)

        df = databricks_consumer.get_data_from_query(self.query)

        format_options = SparkTableStorageFormat.get_storage(self.layer)
        s3_loader = S3Loader()
        s3_loader.load_full_table(
            df,
            self.database_name,
            self.table_name,
            format_options,
            self.database_location,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df,
            self.database_name,
            self.table_name,
            format_options,
            self.database_location,
        )
