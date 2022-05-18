import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_table_in_datalake")

parser = ArgumentParser(description="create_clean_table_in_datalake")
parser.add_argument("table_name")
parser.add_argument("source")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("dag_name")
parser.add_argument("datalake_layer")

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    table_name = args.table_name
    source = args.source
    env = args.env
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    datalake_layer = args.datalake_layer

    query_path = f"{QUERIES_DATALAKE_PATH}/{dag_name}/{datalake_layer}/{table_name}.sql"
    query = FileService.get_query_from_file_name(query_path)

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_clean_databricks"]
    metastore_service.create_database(database_name)

    # create
    # todo: use DatabricksConsumer to read data
    df = spark_client.get_records(query)
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]
    # create database if not exists

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
