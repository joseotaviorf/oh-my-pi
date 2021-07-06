import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.file_service import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_table_in_datalake")

parser = ArgumentParser(description="create_clean_table_in_datalake")
parser.add_argument("table_name")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("schema")

if __name__ == "__main__":
    args = parser.parse_args()
    table_name = args.table_name
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    schema = args.schema

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()

    # todo: use DatabricksConsumer to read data
    query_path = f"{QUERIES_DATALAKE_PATH}{source}/clean/{schema}/{table_name}.sql"
    raw_to_clean_query = FileService.get_query_from_file_name(query_path)
    clean_df = spark_client.get_records(raw_to_clean_query)
    clean_df = SparkDataFrameService(clean_df).optimize_partition(250000).output()

    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    database_name = db_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]
    schema_table_name = f"{schema}_{table_name}"
    s3_loader.load_full_table(
        df=clean_df,
        database_name=database_name,
        table_name=schema_table_name,
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader.update_metastore(
        clean_df, database_name, schema_table_name, format_options, database_location
    )
