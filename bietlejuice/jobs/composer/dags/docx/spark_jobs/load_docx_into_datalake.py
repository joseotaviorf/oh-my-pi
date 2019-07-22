import json
import logging

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import DatabaseEnum, BaseDBUtils
from bietlejuice.jobs.composer.consumers import MySQLConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_docx_into_datalake")

DATABRICKS_SCOPE = "quintoandar-prod"
BLACK_LIST = ["flyway_schema_history"]

if __name__ == "__main__":
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    connection_json = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=DatabaseEnum.DOCX)
    connection = json.loads(connection_json)
    mysql_consumer = MySQLConsumer(connection)

    tables = mysql_consumer.get_table_names_and_sizes().collect()
    loader = DatabaseIntoDataLakeRawLoader()

    for table in tables:
        if table.table_name not in BLACK_LIST:
            loader.load_full_table(consumer=mysql_consumer, table_name=table.table_name)
