import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, MongoClient
from bietlejuice.jobs.composer.consumers.db_consumers import MongoConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_heimdall_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = "heimdall"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    connection_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.HEIMDALL
    )
    connection = json.loads(connection_json)
    mongo_client = MongoClient(connection)
    spark_client = SparkClient()

    mongo_consumer = MongoConsumer(mongo_client, spark_client)
    tables = mongo_consumer.get_table_names_and_sizes().collect()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(db_info["db_raw_databricks"])

    for table in tables:
        df = mongo_consumer.get_data_from_table(table.table_name)
        df = SparkDataFrameService().input(df).optimize_partition(250000).output()

        loader.load_full_table(
            df=df,
            database_name=db_info["db_raw_databricks"],
            table_name=table.table_name.lower(),
            format=SparkTableStorageFormat.DEFAULT_RAW,
            database_location=db_info["db_raw_path"],
        )
