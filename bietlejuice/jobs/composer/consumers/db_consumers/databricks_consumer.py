from pyspark.sql.functions import col, lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.db_consumers.db_consumer import DBConsumer

logger = QuintoAndarLogger("DatabricksConsumer")


class DatabricksConsumer(DBConsumer):
    """
    Gets data from a Databrick Metastore through Spark and returns it as a Spark
    DataFrame.
    :param conn_config: A dict with the config values of the connection. It must
    contain the key `db`.
    :type conn_config: dict
    :param spark_client: A client to handle the Spark connection
    :type spark_client: SparkClient
    """

    def __init__(self, conn_config, spark_client):
        # TODO: Other consumers need a conn_config with a db to connect. As it is not
        #  the case of DatabricksConsumer, we should remove conn_config from this
        #  constructor and send the database on its methods call when necessary
        self.conn_config = conn_config
        self.spark_client = spark_client

    @logger
    def get_table_names_and_sizes(self):
        """
        Gets the table names and sizes in the given database.
        :return: A Spark DataFrame with cols: table_name and size
        """
        query = "show tables in {db}".format(db=self.conn_config["db"])
        df = (
            self.spark_client.get_records(query)
            .select(col("tableName").alias("table_name"))
            .withColumn("size", lit(0))
        )

        return df

    @logger
    def get_table_schema(self, table_name):
        """
        Gets the schema of a table in the given database.
        :param table_name: Name of a table
        :return: A Spark DataFrame with the table schema
        """
        query = "describe {db}.{table}".format(
            db=self.conn_config["db"], table=table_name
        )
        df = (
            self.spark_client.get_records(query)
            .select("col_name", col("data_type").alias("col_type"))
            .filter(col("col_name").rlike(r"^\w"))
            .distinct()
        )

        return df

    @logger
    def get_data_from_table(self, table_name):
        """
        Gets all data from table.
        :param table_name: Name of a table
        :return: A Spark DataFrame with all the data.
        """
        query = f"SELECT * FROM {self.conn_config['db']}.{table_name}"
        df = self.spark_client.get_records(query)

        return df

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        # todo: implement me!
        raise NotImplementedError()

    @logger
    def get_data_from_query(self, query, table_name=None):
        """
        Gets the results of a query.
        :param query: Query content
        :param table_name: Name of the table relevant to the query
        :return: A Spark DataFrame with the query results
        """
        self.spark_client.run("USE {}".format(self.conn_config["db"]))
        df = self.spark_client.get_records(query)

        return df

    @logger
    def get_incremental_data_from_table(self, table_name, column_name, execution_date):
        # todo: implement me!
        raise NotImplementedError()

    @logger
    def get_partition_values_from_table(self, table_name):
        """
        Gets all the partitions created for the table

        :return: A Spark DataFrame with default col partition
        """
        query = f"SHOW PARTITIONS {self.conn_config['db']}.{table_name}"
        df = self.spark_client.get_records(query)

        return df
