import logging

from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

SOURCE = "bigfone"
DATABRICKS_SCOPE = "quintoandar"

base_dbutils = BaseDBUtils()
spark_sql_client = SparkClient()

logging.getLogger("py4j").setLevel(logging.ERROR)
