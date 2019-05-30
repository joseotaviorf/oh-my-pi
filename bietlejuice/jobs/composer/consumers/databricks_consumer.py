from pyspark.sql import SparkSession
from pyspark.sql.functions import lit
from python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.consumer import Consumer

logger = QuintoAndarLogger('DatabricksConsumer')


class DatabricksConsumer(Consumer):

    def __init__(self, db):
        self.db = db

    @logger
    def get_table_names_and_sizes(self):
        spark = SparkSession.builder.getOrCreate()
        result = spark.sql('show tables in ' + self.db) \
            .select("tableName") \
            .withColumn('size', lit(0))

        return result

    @logger
    def get_data_from_table(self, table):
        raise NotImplementedError()

    @logger
    def get_data_from_table_in_parallel(self, table, concurrency):
        raise NotImplementedError()

    @logger
    def get_data_from_query(self, query):
        raise NotImplementedError()

    @logger
    def get_table_schema(self, table):
        spark = SparkSession.builder.getOrCreate()
        result = spark.sql('describe {}.{}'.format(self.db, table)) \
            .select('col_name', 'data_type')

        return result
