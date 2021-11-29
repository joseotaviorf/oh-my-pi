from bietlejuice.jobs.composer.base.spark.spark_table_storage_format import (
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.jobs.composer.services.schema_service import SchemaService


class DefaultRowAdditionPipeline(AbstractPipeline):
    """
    Pipeline responsible for adding a default row with sk = -1 to a dim table.
    """

    def __init__(self, database_name, table_name, database_location, layer):
        """
        :param database_name: database name for the table to be processed
        :param table_name: table name
        :param database_location: database location in S3
        :param layer: layer for database and table to be processed
        """
        self.database_name = database_name
        self.table_name = table_name
        self.database_location = database_location
        self.layer = layer

    def run(self):
        spark_client = SparkClient()
        conn_config = {"db": self.database_name}
        databricks_consumer = DatabricksConsumer(conn_config, spark_client)

        df = databricks_consumer.get_data_from_table(self.table_name)
        df = self.add_default_row(spark_client, df)

        format_options = SparkTableStorageFormat.get_storage(self.layer)
        s3_loader = S3Loader()
        s3_loader.load_full_table(
            df,
            self.database_name,
            self.table_name,
            format_options,
            self.database_location,
        )

    def add_default_row(self, spark_client, dataframe):
        """
        Process dataframe data to add a row with sk = -1 for dimensions.
        :param spark_client: client to manipulate dataframe data
        :param dataframe: the dataframe to be processed
        :return: processed dataframe containing original dataframe plus the new row in case of dimension tables.
        If it is not a dimension, returns original dataframe
        """
        if self.is_dim():
            schema_df = SchemaService.get_schema_from_dataframe_as_string(dataframe)
            sk_col_name = schema_df.split()[0]
            df_insertion = spark_client.create_dataframe(
                data=[{sk_col_name: -1}], schema=schema_df
            )
            return dataframe.union(df_insertion)
        return dataframe

    def is_dim(self):
        return self.table_name.startswith("dim_")
