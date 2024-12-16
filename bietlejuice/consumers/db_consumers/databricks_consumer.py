from pyspark.sql.functions import col, lit
from pyspark.sql.types import StructType, StructField, StringType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.consumers.db_consumers.db_consumer import DBConsumer
from bietlejuice.services.metastore_services import SparkMetastoreService
from pyspark.sql.utils import AnalysisException

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
        try:
            df = self.spark_client.get_records(query)
        except AnalysisException as e:
            if "UC_COMMAND_NOT_SUPPORTED" not in e.getErrorClass():
                raise e
            # Unity catalog doesn't support SHOW PARTITIONS, so we have to list them
            # by searching the objects in the table path
            df = self._get_partition_values_from_table_by_listing_objects(table_name)

        return df

    def _get_partition_values_from_table_by_listing_objects(self, table_name):
        """
        Equivalent to running SHOW PARTITIONS, but for Unity Catalog. It recursively lists directories
        and identifies partitions based on the directory structure.
        """

        # Import needs to be internal, otherwise this class is not serializable
        # it must be serializable, since it is implicitly imported by a Spark job that uses parallelize
        # (sync_metadata.py)
        from bietlejuice.base.spark.base_spark import BaseDBUtils

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()
        spark_metastore_service = SparkMetastoreService(self.spark_client)
        location = spark_metastore_service.get_table_path(
            self.conn_config["db"], table_name
        )
        partition_keys = [
            key_tuple[0]
            for key_tuple in spark_metastore_service.get_table_partition_keys(
                self.conn_config["db"], table_name
            )
        ]
        partition_values = base_dbutils.discover_partition_values_in_path(
            location, dbutils, max_recursive_depth=len(partition_keys)
        )
        partition_values_formatted = []
        for partition_value_list in partition_values:
            partition_values_formatted.append(
                [
                    "/".join(
                        [
                            f"{key}={value}"
                            for key, value in zip(partition_keys, partition_value_list)
                        ]
                    )
                ]
            )
        return self.spark_client.create_dataframe(
            partition_values_formatted,
            StructType([StructField("partition", StringType())]),
        )
