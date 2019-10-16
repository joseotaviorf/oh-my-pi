import logging

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, BaseSparkContext
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient


SPARK, SQLCONTEXT = BaseSparkContext.spark, BaseSparkContext.sqlContext

SOURCE = "bigfone"
DATABRICKS_SCOPE = "quintoandar"

base_dbutils = BaseDBUtils()
spark_sql_client = SparkSQLCLient(SPARK, SQLCONTEXT)

logging.getLogger("py4j").setLevel(logging.ERROR)
