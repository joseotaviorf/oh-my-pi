import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_dw_table_in_datalake")

parser = ArgumentParser(description="create_dw_table_in_datalake")
parser.add_argument("table_name")
parser.add_argument("schema")
parser.add_argument("env")
parser.add_argument("dag_name")

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    table_name = args.table_name
    schema = args.schema
    env = args.env
    dag_name = args.dag_name

    query_path = QUERIES_DATALAKE_PATH + dag_name + "/{}.sql".format(table_name)
    query = FileService.get_query_from_file_name(query_path)

    # setup
    db_info = DatalakeMetastoreService.get_dw_info(env, schema)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader(metastore_service)

    # create
    # todo: use DatabricksConsumer to read data
    df = spark_client.get_records(query)
    df = SparkDataFrameService(df).optimize_partition(250000).output()

    # load
    loader.load_full_table(
        df=df,
        database_name=db_info["dw_schema_databricks"],
        table_name=table_name,
        format=SparkTableStorageFormat.DEFAULT_DW,
        database_location=db_info["dw_schema_path"],
    )
