import re
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_sauron_into_datalake"
RESTRICTED_NAMES = ("django_", "auth_")

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = "sauron"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.SAURON)
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader(metastore_service)

    for table in tables:
        table_name = table.table_name.lower()
        if not table_name.startswith(RESTRICTED_NAMES) and not bool(
            re.search(r"(\d+)$", table_name)
        ):
            df = postgres_consumer.get_data_from_table(table.table_name)
            loader.load_full_table(
                df=df,
                database_name=db_info["db_raw_databricks"],
                table_name=table.table_name.lower(),
                format=SparkTableStorageFormat.DEFAULT_RAW,
                database_location=db_info["db_raw_path"],
            )
