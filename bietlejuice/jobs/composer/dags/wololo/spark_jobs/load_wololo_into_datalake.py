import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_wololo_into_datalake"
BLOCK_LIST = ["change_owner_control", "flyway_schema_history", "inboundeventhistory"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source

    logger.info(
        f"""
                m=__main__, environment={environment}, datalake_bucket={datalake_bucket},
                source={source}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.WOLOLO)
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    for table in tables:
        if table.table_name not in BLOCK_LIST:
            concurrent_tasks = spark_client._session.sparkContext.defaultParallelism * 2
            df = postgres_consumer.get_data_from_table_in_parallel(
                table.table_name, concurrent_tasks
            )
            database_name = db_info["db_raw_databricks"]
            format_options = SparkTableStorageFormat.DEFAULT_RAW
            database_location = db_info["db_raw_path"]

            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table.table_name.lower()}",
                format_options=format_options,
            )

            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table.table_name.lower(),
                format_options,
                database_location,
            )
