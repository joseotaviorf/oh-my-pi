import logging
from argparse import ArgumentParser
from datetime import datetime

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
logger = QuintoAndarLogger("create_clean_incremental_table_in_datalake")

parser = ArgumentParser(description="create_clean_incremental_table_in_datalake")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("source")
parser.add_argument("table_name")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    source = args.source
    table_name = args.table_name
    partition_by = args.partition_by

    logger.info(
        "m=__main__, date={}, source={}, table_name={}, msg=Job started".format(
            execution_date, source, table_name
        )
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    metastore_service = SparkMetastoreService(
        db_info["db_clean_databricks"],
        db_info["db_clean_path"],
        SparkSQLCLient(spark, sqlContext),
    )
    s3_loader = S3Loader(metastore_service)

    query_path = QUERIES_DATALAKE_PATH + source + "/{}.sql".format(table_name)
    query = FileService.get_query_from_file_name(query_path).format(
        db=db_info["db_raw_databricks"], year=year, month=month, day=day
    )

    # create df
    df = SparkDataFrameService(spark.sql(query)).optimize_partition(250000).output()

    # load df
    s3_loader.load_incremental_table(
        df, table_name, SparkTableStorageFormat.DEFAULT_CLEAN, partition_by
    )

    # add new partition
    metastore_service.create_new_partitions_from_df(
        table_name, df, partition_by, parallelism=1
    )
