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
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.dags.cidade_alerta import (
    SOURCE,
    INCREMENTAL_TABLES,
    INCREMENTAL_COLUMNS_MAPPING,
)

JOB_NAME = "load_incremental_tables_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("execution_date", type=str, help="DAG execution date")

    args = parser.parse_args()
    environment = args.env
    execution_date = args.execution_date

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partition_cols = ["year", "month", "day"]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.CIDADE_ALERTA
    )
    conn_config = json.loads(conn_config_json)

    mongo_client = MongoClient(conn_config)
    spark_client = SparkClient()
    mongo_consumer = MongoConsumer(mongo_client, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE)
    spark_metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(db_info["db_raw_databricks"])

    for table_name in INCREMENTAL_TABLES:

        df = mongo_consumer.get_incremental_data_from_table(
            table_name, INCREMENTAL_COLUMNS_MAPPING[table_name], execution_date
        )

        if df is not None:
            df = (
                SparkDataFrameService()
                .input(df)
                .optimize_partition(200000)
                .create_year_month_day_columns_from_date(dt_execution)
                .output()
            )

            loader.load_incremental_table(
                df=df,
                database_name=db_info["db_raw_databricks"],
                table_name=table_name,
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                database_location=db_info["db_raw_path"],
                partition_cols=partition_cols,
                schema_merging=True,
            )

            spark_metastore_service.create_new_partitions_from_df(
                database_name=db_info["db_raw_databricks"],
                table_name=table_name,
                df=df,
                partition_cols=partition_cols,
            )
