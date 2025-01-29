import json
import logging

from argparse import ArgumentParser
from datetime import datetime
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient

from bietlejuice.consumers.db_consumers import PostgresConsumer

from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services.metastore_services import SparkMetastoreService

from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

from bietlejuice.base.db import QUERIES_DATALAKE_PATH

JOB_NAME = "load_incremental_data_into_datalake_raw"

QUERIES_METABASE_DATALAKE_PATH = QUERIES_DATALAKE_PATH + "metabase"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="table name")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("date_filter_column", help="Date column to be filtered")

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    date_filter_column = args.date_filter_column
    table_name = args.table_name.lower()

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"execution_date={execution_date}, table_name={table_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", (dt_execution.year)),
            ("month", (dt_execution.month)),
            ("day", (dt_execution.day)),
        ]
    )

    partition_cols = list(partitions.keys())

    conn_config = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.METABASE)
    conn_config_json = json.loads(conn_config)
    spark_client = SparkClient()

    consumer = PostgresConsumer(conn_config_json, spark_client)

    df = consumer.get_incremental_data_from_table(
        table_name=table_name,
        date_filter_column=date_filter_column,
        date_filter_value=execution_date,
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(db_info["db_raw_databricks"])

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
        force_recreate=False,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )

    spark_metastore_service.refresh_table(database_name, table_name)
