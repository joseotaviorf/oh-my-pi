import logging

from bietlejuice.jobs.composer.base.spark import BaseDBUtils

SOURCE = "bigfone"
DATABRICKS_SCOPE = "quintoandar"

base_dbutils = BaseDBUtils()

logging.getLogger("py4j").setLevel(logging.ERROR)
