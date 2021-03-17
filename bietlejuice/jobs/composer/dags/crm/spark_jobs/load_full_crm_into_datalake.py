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

JOB_NAME = "load_full_crm_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

TABLES = ["tasktitles", "workgroups"]

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("source")
    parser.add_argument("datalake_bucket")

    args = parser.parse_args()
    environment = args.env
    source = args.source
    data_lake_bucket = args.datalake_bucket

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
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(SparkClient())

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()

    for table_name in TABLES:
        df = mongo_consumer.get_data_from_table(table_name)

        if not df.rdd.isEmpty():
            s3_loader.load_full_table(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=format_options,
                database_location=database_location,
            )
            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                force_recreate=False,
            )
