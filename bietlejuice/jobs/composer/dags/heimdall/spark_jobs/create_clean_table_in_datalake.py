import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_table_in_datalake")

parser = ArgumentParser(description="create_clean_table_in_datalake")
parser.add_argument("source")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("dag_name")

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    source = args.source
    env = args.env
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    table_name = "activity"

    query_path = QUERIES_DATALAKE_PATH + dag_name + "/{}.sql".format(table_name)
    query = FileService.get_query_from_file_name(query_path)

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader(metastore_service)

    # create
    df = spark_client.get_records(query)
    df = SparkDataFrameService(df).optimize_partition(250000).output()

    # load
    loader.load_full_table(
        df=df,
        database_name=db_info["db_clean_databricks"],
        table_name=table_name,
        format=SparkTableStorageFormat.DEFAULT_CLEAN,
        database_location=db_info["db_clean_path"],
    )
