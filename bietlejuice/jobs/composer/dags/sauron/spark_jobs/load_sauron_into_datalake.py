import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

SOURCE = "sauron"
JOB_NAME = "load_sauron_into_datalake"
TABLE_MAPPING = {
    "activesessions": "active_sessions",
    "botoutgoingmessages": "bot_outgoing_messages",
    "expiredsessions": "expired_sessions",
    "incomingmessagestatus": "incoming_message_status",
    "incomingmessages": "incoming_messages",
    "session": "session",
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

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    allow_list = TABLE_MAPPING.keys()
    for table in tables:
        if table.table_name.lower() in allow_list:
            df = postgres_consumer.get_incremental_data_from_table(
                table.table_name, "updated_at", execution_date
            )
            # the table names in the datalake must be lowercase
            s3_loader.load_incremental_table(
                df=df,
                database_name=database_name,
                table_name=TABLE_MAPPING[table.table_name.lower()],
                format_options=format_options,
                database_location=database_location,
                partition_cols=partition_cols,
            )
            metastore_service.create_new_partitions_from_df(
                database_name, table.table_name.lower(), df, partition_cols
            )
