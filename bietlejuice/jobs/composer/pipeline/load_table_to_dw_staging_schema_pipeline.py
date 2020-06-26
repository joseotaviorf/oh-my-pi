from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.pipeline.load_table_to_dw_pipeline import (
    LoadTableToDWPipeline,
)
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.services.schema_service import SchemaService


class LoadTableToDWStagingSchemaPipeline(LoadTableToDWPipeline):
    """
    Class to load models to DW staging schema metastore loading from a specified query.
    """

    def __init__(
        self, schema_database_name, table_name, schema_database_location, query_path
    ):
        """
        :param schema_database_name: schema name for database in metastore
        :param table_name: table name in metastore
        :param schema_database_location: schema location in S3
        :param query_path: query path for specified table query
        """
        super().__init__(
            schema_database_name,
            table_name,
            schema_database_location,
            SparkTableStorageFormat.DEFAULT_DW_STAGING,
        )
        self.query_path = query_path

    def get_data(self, databricks_consumer, table_name):
        """
        Load table data in a dataframe using specified query for table.
        :param databricks_consumer: consumer to read dataframe from spark metastore
        :param table_name: table name to load
        :return: dataframe data
        """
        query = FileService.get_query_from_file_name(self.query_path)
        return databricks_consumer.get_data_from_query(query)

    def add_default_row(self, spark_client, dataframe):
        """
        Process  dataframe data to add a row with sk = -1 for dimensions.
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
        """
        Verifies if table is a dimension or not by its name.
        :return: True if it is a dimension, False otherwise
        """
        return self.table_name.startswith("dim_")
