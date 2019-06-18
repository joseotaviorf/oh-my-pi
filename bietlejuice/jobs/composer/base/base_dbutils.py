from pyspark.context import SparkContext
from quintoandar.python_logger import QuintoAndarLogger

logger = QuintoAndarLogger('BaseDBUtils')


class BaseDBUtils:
    @logger(exclude_return=True)
    def get_dbutils(self):
        spark = SparkContext.getOrCreate()
        setting = spark.getConf().get("spark.master")
        if 'local' in setting:
            from pyspark.dbutils import DBUtils
            logger.info('m=get_db_utils, msg=returning local dbutils reference')
            return DBUtils(spark.sparkContext)

        logger.info('m=get_db_utils, msg=dbutils already available')
