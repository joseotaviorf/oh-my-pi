from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("SparkMetastoreLoader")


class SparkMetastoreLoader:
    @staticmethod
    def save_as_table(df, database_name, table_name):
        """
        Save the contents of the Spark DataFrameWriter to a data source as a table

        If the table already exits, this method overwrites the existing data while
        recreates the table with the schema of the DataFrameWriter.
        :param df: a dataframe writer
        :type df: DataFrameWriter
        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :return: None
        """

        if not df:
            raise ValueError("m=save_as_table, msg=Spark DataFrame is empty")
        if not isinstance(database_name, str):
            raise ValueError("m=save_as_table, msg=database needs to be a string")
        if not isinstance(table_name, str):
            raise ValueError("m=save_as_table, msg=table_name needs to be a string")

        name = "{}.{}".format(database_name, table_name)
        df.saveAsTable(name)

        logger.info(
            "m=save_as_table, table={}, " "msg=successfully loaded table.".format(name)
        )
