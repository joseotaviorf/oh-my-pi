import json
import logging
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import MySqlConsumer

JOB_NAME = "load_full_atta_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("db")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    db = args.db

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, db={db} msg=Starting full Spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.ATTA)
    conn_config = json.loads(conn_config_json)
    conn_config['db'] = db
    mysql_consumer = MySqlConsumer(conn_config, SparkClient())

    df = mysql_consumer.get_data_from_table(table_name)

    if df:
        logger.warning(
            f"""m=__main__, table_name={table_name}, msg=Data exists in the extraction, count={df.count()}"""
        )
    else:
        logger.warning(
            f"""m=__main__, table_name={table_name}, msg=No data returned from Production database."""
        )
