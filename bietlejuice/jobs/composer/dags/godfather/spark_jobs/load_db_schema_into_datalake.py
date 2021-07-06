import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_db_schema_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("schema")

if __name__ == "__main__":
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    schema = args.schema

    # setup
    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.GODFATHER
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)
    postgres_consumer.conn_config["schema"] = schema

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # load db schema into datalake
    tables = [
        row.table_name
        for row in postgres_consumer.get_table_names_and_sizes().collect()
    ]
    logger.info(
        f"m=__main__, schema={schema}, tables={tables}, msg=Loading tables in "
        f"datalake raw"
    )
    for table_name in tables:
        df = postgres_consumer.get_data_from_table(table_name)
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        database_location = db_info["db_raw_path"]
        # the table names in the datalake must be lowercase
        schema_table_name = f"{schema}_{table_name}".lower()
        database_name = db_info["db_raw_databricks"]
        s3_loader.load_full_table(
            df=df,
            database_name=database_name,
            table_name=schema_table_name,
            format_options=format_options,
            database_location=database_location,
        )

        spark_metastore_loader.update_metastore(
            df, database_name, schema_table_name, format_options, database_location
        )
