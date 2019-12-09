import logging
from datetime import datetime
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import (
    sqlContext,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_staging_repartitioned_table")

parser = ArgumentParser(description="create_clean_staging_repartitioned_table")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("source")
parser.add_argument("source_table_name")
parser.add_argument("target_table_name")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    source = args.source
    source_table_name = args.source_table_name
    target_table_name = args.target_table_name
    partition_by = args.partition_by

    logger.info(
        "m=__main__, date={}, source={}, target_table_name={}, "
        "target_table_name{}, partition_by={}, msg=Job started".format(
            execution_date, source, source_table_name, target_table_name, partition_by
        )
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    spark_client = SparkClient()
    dataframe_service = SparkDataFrameService()
    metastore_service = SparkMetastoreService(spark_client)

    loader = S3Loader(metastore_service)

    # create df
    df = sqlContext.table(
        "{}.{}".format(db_info["db_clean_databricks"], source_table_name)
    ).where("year = {} and month = {} and day = {}".format(year, month, day))

    df_repartitioned = (
        SparkDataFrameService(df)
        .optimize_partitions_by_partition_columns(partition_by)
        .output()
    )

    # load df
    # TODO: this method will create a table in metastore in the first execution,
    #  but this table will never be used. The best would be have a method that
    #  only writes the files, but this needs to be discussed yet. For now it's
    #  not a big deal
    loader.load_incremental_table(
        df=df_repartitioned,
        database_name=db_info["db_clean_staging_databricks"],
        table_name=target_table_name,
        format_options=SparkTableStorageFormat.DEFAULT_CLEAN,
        database_location=db_info["db_clean_staging_path"],
        partition_cols=partition_by,
    )

    metastore_service.refresh_table(
        db_info["db_clean_staging_databricks"], target_table_name
    )
