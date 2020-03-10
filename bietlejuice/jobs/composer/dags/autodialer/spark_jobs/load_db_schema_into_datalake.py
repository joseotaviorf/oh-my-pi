import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import MongoClient, SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import MongoConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_db_schema_into_datalake"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

PERMISSION_LIST = [
    "taskReferenceInboundEventHistories",
    "taskReferenceOutboundHistory",
    "taskReferences",
]

if __name__ == "__main__":
    logger.info("m=__main__, msg=Extracting tables.")

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("data_lake_bucket")
    parser.add_argument("source")
    args = parser.parse_args()
    environment = args.env
    data_lake_bucket = args.data_lake_bucket
    source = args.source

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.AUTODIALER)
    mongo_consumer = MongoConsumer(
        mongo_client=MongoClient(conn_config=json.loads(conn_config)),
        spark_client=SparkClient(),
    )

    for table in PERMISSION_LIST:
        df = mongo_consumer.get_data_from_table(table)
        df = SparkDataFrameService().input(df).optimize_partition(200000).output()

        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, data_lake_bucket
        )
        metastore_service = SparkMetastoreService(SparkClient())
        s3_loader = S3Loader(metastore_service)
        s3_loader.load_full_table(
            df=df,
            database_name=db_info["db_raw_databricks"],
            table_name=table,
            format=SparkTableStorageFormat.DEFAULT_RAW,
            database_location=db_info["db_raw_path"],
            schema_merging=True,
        )

    logger.info("m=__main__, msg=Tables successfully loaded to data lake raw.")
