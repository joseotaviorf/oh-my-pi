from abc import abstractmethod

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader, S3Loader
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


class LoadTableToDWPipeline(AbstractPipeline):
    """
    Abstract class to load DW models in spark metastore databases
    """

    def __init__(
        self, schema_database_name, table_name, schema_database_location, format_options
    ):
        """
        :param schema_database_name: schema name for database in metastore
        :param table_name: table name in metastore
        :param schema_database_location: schema database location in S3
        :param format_options: file format in S3
        """
        self.schema_database_name = schema_database_name
        self.table_name = table_name
        self.schema_database_location = schema_database_location
        self.format_options = format_options

    def run(self):
        """
        Creates the table in spark metastore based in the query from query_path
        """
        spark_client = SparkClient()
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(self.schema_database_name)

        conn_config = {"db": self.schema_database_name}
        databricks_consumer = DatabricksConsumer(conn_config, spark_client)

        df = self.get_data(databricks_consumer, self.table_name)
        df = self.add_default_row(spark_client, df)

        s3_loader = S3Loader()
        s3_loader.load_full_table(
            df,
            self.schema_database_name,
            self.table_name,
            self.format_options,
            self.schema_database_location,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df,
            self.schema_database_name,
            self.table_name,
            self.format_options,
            self.schema_database_location,
        )

    @abstractmethod
    def get_data(self, databricks_consumer, table_name):
        """
        Load table data in a dataframe following specified layer logic (staging or final schema)
        It must be implemented in each concrete class.
        :param databricks_consumer: consumer to read dataframe from spark metastore
        :param table_name: table name to load
        :return: dataframe data
        """
        raise NotImplementedError()

    def add_default_row(self, spark_client, dataframe):
        """
        Adds default row into dataframe following specific layer logic (staging or final schema)
        If it is not overwritten in child classes it assumes default behavior and returns the same dataframe passed
        as parameter.
        :param spark_client: client to manipulate dataframe data
        :param dataframe: the dataframe to be processed
        :return: processed dataframe
        """
        return dataframe
