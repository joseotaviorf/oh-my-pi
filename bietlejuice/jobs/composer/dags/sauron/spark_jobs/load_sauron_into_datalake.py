import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

SOURCE = "sauron"
JOB_NAME = "load_sauron_into_datalake"
TABLES_DICT = {
    "activesessions": {"table_name": "ActiveSessions"},
    "botoutgoingmessages": {
        "table_name": "BotOutgoingMessages_{year}{month}",
        "partitioned_table": True,
    },
    "expiredsessions": {"table_name": "ExpiredSessions"},
    "incomingmessagestatus": {
        "table_name": "IncomingMessageStatus_{year}{month}",
        "partitioned_table": True,
    },
    "incomingmessages": {
        "table_name": "IncomingMessages_{year}{month}",
        "partitioned_table": True,
    },
    "session": {"table_name": "Session"},
}


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partition_cols = ["year", "month", "day"]

    logger.info(
        f"m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, "
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.SAURON)
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    for datalake_table_name, table_info in TABLES_DICT.items():
        sauron_table_name = table_info.get("table_name")
        if table_info.get("partitioned_table"):
            # TODO: remove this once the table permission has been fixed for 2022-01 tables
            if dt_execution.year == 2022 and dt_execution.month == 1:
                continue
            sauron_table_name = sauron_table_name.format(
                year=dt_execution.year, month="{:02d}".format(dt_execution.month)
            )

        df = postgres_consumer.get_incremental_data_from_table(
            sauron_table_name, "updated_at", execution_date
        )
        s3_loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=datalake_table_name,
            format_options=format_options,
            database_location=database_location,
            partition_cols=partition_cols,
        )
        metastore_service.create_new_partitions_from_df(
            database_name, datalake_table_name, df, partition_cols
        )
