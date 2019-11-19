import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkMetastoreService,
    SparkTableStorageFormat,
    spark,
    sqlContext,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient

JOB_NAME = "load_retsuko_into_datalake"
BLACK_LIST = ["schema_migrations"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "retsuko"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.RETSUKO
    )
    conn_config = json.loads(conn_config_json)
    postgres_consumer = PostgresConsumer(conn_config, SparkClient())

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    spark_metastore_service = SparkMetastoreService(
        db_info["db_raw_databricks"],
        db_info["db_raw_path"],
        SparkSQLCLient(spark, sqlContext),
    )
    loader = S3Loader(spark_metastore_service)

    for table in tables:
        if table.table_name not in BLACK_LIST:
            df = postgres_consumer.get_data_from_table(table.table_name)
            loader.load_full_table(
                df, table.table_name, SparkTableStorageFormat.DEFAULT_RAW
            )
