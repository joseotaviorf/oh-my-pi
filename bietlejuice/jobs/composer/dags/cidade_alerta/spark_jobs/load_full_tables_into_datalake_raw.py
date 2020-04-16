import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, MongoClient
from bietlejuice.jobs.composer.consumers.db_consumers import MongoConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.dags.cidade_alerta import (
    BLOCK_TABLES,
    INCREMENTAL_TABLES,
)

JOB_NAME = "load_full_tables_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = "cidade_alerta"

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

    tables = mongo_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    BLOCK_LIST = BLOCK_TABLES + INCREMENTAL_TABLES

    for table in tables:

        # there are different tables between forno and prod environments
        if table.table_name not in BLOCK_LIST and table.size > 0:
            df = mongo_consumer.get_data_from_table(table.table_name)
            df = SparkDataFrameService().input(df).optimize_partition(200000).output()

            loader.load_full_table(
                df=df,
                database_name=database_name,
                table_name=table.table_name,
                format_options=format_options,
                database_location=database_location,
                schema_merging=True,
            )

            spark_metastore_loader.save_as_table(
                df, database_name, table.table_name, format_options, database_location
            )
