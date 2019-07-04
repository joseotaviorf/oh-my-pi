import json
import logging

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import DatabaseEnum, BaseDBUtils
from bietlejuice.jobs.composer.consumers import MySQLConsumer
from bietlejuice.jobs.composer.etl import DataSourceIntoDataLakeLoader

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_docx_into_datalake")

BLACK_LIST = ["flyway_schema_history"]

DATABRICKS_SCOPE = "quintoandar-forno"


if __name__ == "__main__":
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    connection_json = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=DatabaseEnum.DOCX)
    connection = json.loads(connection_json)
    mysql_consumer = MySQLConsumer(connection)

    tables = DataSourceIntoDataLakeLoader.get_table_names_and_sizes(
        mysql_consumer
    ).collect()

    for table in tables:
        DataSourceIntoDataLakeLoader.load_full_table_into_datalake_raw(
            table_name=table.table_name, consumer=mysql_consumer
        )
