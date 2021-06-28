import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, MongoClient
from bietlejuice.jobs.composer.consumers.db_consumers import MongoConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService

JOB_NAME = "load_incremental_crm_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name", help="table name")
    parser.add_argument("date_filter_column", help="Date filter column")
    parser.add_argument("execution_date", type=str, help="DAG execution date")

    args = parser.parse_args()
    environment = args.env
    source = args.source
    data_lake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    table_name = args.table_name
    date_filter_column = args.date_filter_column

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.CRM)
    conn_config_json = json.loads(conn_config)
    mongo_consumer = MongoConsumer(
        mongo_client=MongoClient(conn_config_json), spark_client=SparkClient()
    )

    db_info = DatalakeMetastoreService.get_db_info(
        environment, source, data_lake_bucket
    )
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(SparkClient())

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    partition_cols = ["year", "month", "day"]
    s3_loader = S3Loader()

    df = mongo_consumer.get_incremental_data_from_table(
        table_name, date_filter_column, execution_date
    )

    if df is not None:
        df = (
            SparkDataFrameService()
            .input(df)
            .optimize_partition(10000)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )
        s3_loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partition_cols=partition_cols,
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
