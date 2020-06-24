from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.pipeline.load_table_to_dw_pipeline import (
    LoadTableToDWPipeline,
)


class LoadTableToDWFinalSchemaPipeline(LoadTableToDWPipeline):
    """
    Class to load models to DW final schema metastore from staging schema metastore.
    """

    def __init__(
        self,
        schema_database_name,
        table_name,
        schema_database_location,
        database_name_staging,
    ):
        """
        :param schema_database_name: schema name for database in metastore
        :param table_name: table name in metastore
        :param schema_database_location: schema location in S3
        :param database_name_staging: schema name for staging database in metastore
        """
        super().__init__(
            schema_database_name,
            table_name,
            schema_database_location,
            SparkTableStorageFormat.DEFAULT_DW,
        )
        self.database_name_staging = database_name_staging

    def get_data(self, databricks_consumer, table_name):
        """
        Load table data in a dataframe querying from staging database.
        :param databricks_consumer: consumer to read dataframe from spark metastore
        :param table_name: table name to load
        :return: dataframe data
        """
        query = f"SELECT * FROM {self.database_name_staging}.{table_name}"
        return databricks_consumer.get_data_from_query(query)
