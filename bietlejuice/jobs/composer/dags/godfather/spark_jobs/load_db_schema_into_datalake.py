import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.base.spark import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.base.spark import spark, sqlContext
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient

JOB_NAME = "load_godfather_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("source")
parser.add_argument("schema")

if __name__ == "__main__":
    args = parser.parse_args()
    environment = args.env
    source = args.source
    schema = args.schema

    # setup
    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.GODFATHER
    )
    conn_config = json.loads(conn_config_json)
    postgresql_consumer = PostgresConsumer(conn_config, SparkClient())
    postgresql_consumer.conn_config["schema"] = schema

    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    metastore_service = SparkMetastoreService(
        db_info["db_raw_databricks"], db_info["db_raw_path"], spark_sql_client
    )
    loader = SparkDataframeIntoDatalakeLoader(
        SparkTableStorageFormat.DEFAULT_RAW, metastore_service
    )

    # load db schema into datalake
    tables = [
        row.table_name
        for row in postgresql_consumer.get_table_names_and_sizes().collect()
    ]
    logger.info(
        "m=__main__, schema={}, tables={}, msg=Loading tables in datalake raw".format(
            schema, tables
        )
    )
    for table in tables:
        df = postgresql_consumer.get_data_from_table(table)
        loader.overwrite_table(df, "{}_{}".format(schema, table))
