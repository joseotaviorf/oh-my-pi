from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("SparkMetastoreLoader")


class SparkMetastoreLoader:
    """
    Loads Spark DataFrames into Spark Metastore as a table.

    :param metastore_service: service to interact with the Spark Metastore
    :type metastore_service: SparkMetastoreService
    """

    def __init__(self, metastore_service):
        self.metastore_service = metastore_service

    def save_as_table(
        self,
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions=[],
        schema_merging=False,
        **options
    ):
        """
        Save the contents of the Spark Dataframe to a data source as a table.
        It merges dataframe schema with existing table schema if asked to.

        If the table already exits, this method overwrites the existing data while
        recreates the table with the schema of the Dataframe.
        :param df: a dataframe
        :type df: DataFrame
        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param format_options: the file format options used to save
        :type format_options: str
        :param database_location: location of the database in the object storage
        :type database_location: str
        :param partitions: names of partitioning columns
        :param schema_merging: enables the schema merging between the table in the
        Spark Metastore and the Spark DataFrame
        :type schema_merging: bool
        :param options: all other string options
        :type partitions: list
        :return: None
        """

        if not df:
            raise ValueError("m=save_as_table, msg=Spark DataFrame is empty")
        if not isinstance(database_name, str):
            raise ValueError("m=save_as_table, msg=database needs to be a string")
        if not isinstance(table_name, str):
            raise ValueError("m=save_as_table, msg=table_name needs to be a string")
        if not isinstance(format_options, str):
            raise ValueError("m=save_as_table, msg=format_options needs to be a string")
        if not isinstance(database_location, str):
            raise ValueError(
                "m=save_as_table, msg=database_location needs to be a string"
            )

        s3_path = database_location + table_name
        if schema_merging and table_name in self.metastore_service.get_table_names(
            database_name
        ):
            table_schema = self.metastore_service.get_table_schema(
                database_name, table_name
            )
            new_schema = self.metastore_service.merge_table_and_dataframe_schemas(
                database_name, table_name, df
            )
            if new_schema != table_schema:
                self.metastore_service.drop_table(database_name, table_name)
                self.metastore_service.create_external_table(
                    database_name=database_name,
                    table_name=table_name,
                    table_location=s3_path,
                    table_schema=new_schema,
                    partition_cols=partitions,
                    format_options=format,
                )
                self.metastore_service.repair_table_partitions(
                    database_name, table_name
                )

            logger.info(
                "m=load_incremental_table, db={}, table_name={}, msg=updating relevant "
                "partitions with the DataFrame content".format(
                    database_name, table_name
                )
            )
        else:
            name = "{}.{}".format(database_name, table_name)
            self.metastore_service.drop_table(database_name, table_name)
            df_writer = (
                df.write.mode("ignore").format(format_options).option("path", s3_path)
            )
            if partitions:
                df_writer = df_writer.partitionBy(*partitions)

            for op, val in options.items():
                df_writer = df_writer.option(op, val)

            df_writer.saveAsTable(name)

            logger.info(
                "m=save_as_table, table={}, "
                "msg=successfully loaded table.".format(name)
            )
