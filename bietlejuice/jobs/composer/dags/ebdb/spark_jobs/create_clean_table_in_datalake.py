import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.base.etl import FileService
from bietlejuice.jobs.composer.base.spark import (
    SparkDataFrameService,
    SparkMetastoreService,
    SparkTableStorageFormat,
    spark,
    sqlContext,
)
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_table_in_datalake")

parser = ArgumentParser(description="create_clean_table_in_datalake")
parser.add_argument("table_name")
parser.add_argument("source")
parser.add_argument("env")
parser.add_argument("dag_name")

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    table_name = args.table_name
    source = args.source
    env = args.env
    dag_name = args.dag_name

    query_path = QUERIES_DATALAKE_PATH + dag_name + "/{}.sql".format(table_name)
    query = FileService.get_query_from_file_name(query_path)

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    metastore_service = SparkMetastoreService(
        db_info["db_clean_databricks"],
        db_info["db_clean_path"],
        SparkSQLCLient(spark, sqlContext),
    )
    loader = S3Loader(metastore_service)

    # create
    df = SparkDataFrameService(spark.sql(query)).optimize_partition(250000).output()

    # load
    loader.load_full_table(df, table_name, SparkTableStorageFormat.DEFAULT_CLEAN)
