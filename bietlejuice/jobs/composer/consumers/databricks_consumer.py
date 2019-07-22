from pyspark.sql import SparkSession
from pyspark.sql.functions import lit, col
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.database_consumer import DatabaseConsumer

logger = QuintoAndarLogger("DatabricksConsumer")


class DatabricksConsumer(DatabaseConsumer):
    def __init__(self, connection):
        self.connection = connection

    @logger
    def get_table_names_and_sizes(self):
        spark = SparkSession.builder.getOrCreate()
        result = (
            spark.sql("show tables in " + self.connection["db"])
            .select(col("tableName").alias("table_name"))
            .withColumn("size", lit(0))
        )

        return result

    @logger
    def get_table_schema(self, table_name):
        spark = SparkSession.builder.getOrCreate()
        result = (
            spark.sql("describe {}.{}".format(self.connection["db"], table_name))
            .select("col_name", col("data_type").alias("col_type"))
            .filter(col("col_name").rlike(r"^\w"))
            .distinct()
        )

        return result

    @logger
    def get_data_from_table(self, table_name):
        raise NotImplementedError()

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        raise NotImplementedError()

    @logger
    def get_data_from_query(self, query):
        raise NotImplementedError()
