import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import (
    spark,
    sqlContext,
    SparkMetastoreService,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.etl import FileService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH

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
    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    metastore_service = SparkMetastoreService(
        db_info["dw_schema_databricks"], db_info["dw_schema_path"], spark_sql_client
    )
    loader = SparkDataframeIntoDatalakeLoader(
        SparkTableStorageFormat.DEFAULT_CLEAN, metastore_service
    )

    # create
    df = SparkDataFrameService(spark.sql(query)).optimize_partition(250000).output()

    # load
    loader.overwrite(df, table_name)
