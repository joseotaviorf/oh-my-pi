from pyspark.sql import SparkSession
from pyspark.sql.functions import lit, col
from quintoandar.python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.consumer import Consumer

logger = QuintoAndarLogger('DatabricksConsumer')


class DatabricksConsumer(Consumer):

    def __init__(self, connection):
        self.connection = connection

    @logger
    def get_table_names_and_sizes(self):
        spark = SparkSession.builder.getOrCreate()
        result = spark.sql('show tables in ' + self.connection['db']) \
            .select("tableName") \
            .withColumn('size', lit(0))

        return result

    @logger
    def get_table_schema(self, table):
        spark = SparkSession.builder.getOrCreate()
        result = spark.sql('describe {}.{}'.format(self.connection['db'], table)) \
            .select('col_name', 'data_type') \
            .filter(col('col_name').rlike(r'^\w')) \
            .distinct()

        return result
