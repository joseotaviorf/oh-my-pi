import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer

from bietlejuice.jobs.composer.base.db.database_enum import DatabaseEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)

JOB_NAME = "load_full_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("table_name", help="table name")

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name.lower()

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.SAURON)
    conn_config_json = json.loads(conn_config)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config_json, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    metastore_service = SparkMetastoreService(SparkClient())
    metastore_service.create_database(database_name)

    df = postgres_consumer.get_data_from_table(table_name)
    df = SparkDataFrameService().input(df).optimize_partition(200000).output()

    s3_loader = S3Loader()
    s3_loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
