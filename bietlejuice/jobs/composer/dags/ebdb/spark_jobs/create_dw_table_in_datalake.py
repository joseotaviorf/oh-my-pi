import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DWMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_dw_table_in_datalake")

parser = ArgumentParser(description="create_dw_table_in_datalake")
parser.add_argument("table_name")
parser.add_argument("dw_bucket")
parser.add_argument("schema")
parser.add_argument("env")
parser.add_argument("dag_name")

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    table_name = args.table_name
    dw_bucket = args.dw_bucket
    schema = args.schema
    env = args.env
    dag_name = args.dag_name

    query_path = f"{QUERIES_DATALAKE_PATH}{dag_name}/dw/{table_name}.sql"
    query = FileService.get_query_from_file_name(query_path)

    # setup
    db_info = DWMetastoreService.get_dw_info(env, schema, dw_bucket)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create
    # todo: use DatabricksConsumer to read data
    df = spark_client.get_records(query)
    df = SparkDataFrameService(df).optimize_partition(250000).output()

    # load
    database_name = db_info["dw_schema_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_DW
    database_location = db_info["dw_schema_path"]
    metastore_service.create_database(database_name)

    s3_loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
