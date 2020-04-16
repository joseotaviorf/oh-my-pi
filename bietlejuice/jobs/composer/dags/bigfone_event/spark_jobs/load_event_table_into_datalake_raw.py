import json
from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.dags.bigfone_event import (
    QUERIES_BIGFONE_EVENT_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.dags.bigfone_event.spark_jobs import (
    DATABRICKS_SCOPE,
    SOURCE,
    base_dbutils,
)
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_event_table_into_datalake_raw"
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description="load_event_table_into_datalake_raw")

    # args passed by Airflow task
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")

    args = parser.parse_args()

    logger.info(
        "m=__main__, execution_date={}, environment={}, msg=print args spark jobs "
        "params".format(args.execution_date, args.environment)
    )

    execution_date = args.execution_date
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    table_name = "event"

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    query_filter = OrderedDict(
        [
            ("year", int(dt_execution.year)),
            ("month", int(dt_execution.month)),
            ("day", int(dt_execution.day)),
        ]
    )

    # creation date and event type partitions
    partition_cols = list(query_filter.keys())
    partition_cols.append("event")

    # get query to create event table
    query = FileService().get_query_from_file_name(
        QUERIES_BIGFONE_EVENT_DATALAKE_PATH + "/raw/" + table_name + ".sql"
    )

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # get BigFone credentials stored in Databricks secrets
    conn_config_json = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=SOURCE)

    # establish connection and get data from Event table
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    consumer = PostgresConsumer(conn_config, spark_client)
    event_table_data = consumer.get_data_from_query(query.format(**query_filter))

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, SOURCE, datalake_bucket
    )

    metastore_service = SparkMetastoreService(spark_client)

    # create database if not exists
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    metastore_service.create_database(database_name)

    # loaders
    loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    loader.load_incremental_table(
        df=event_table_data,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partition_cols=partition_cols,
    )

    spark_metastore_loader.save_as_table(
        event_table_data,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
        schema_merging=True,
    )
    # create partition into spark table
    metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=event_table_data,
        partition_cols=partition_cols,
    )
