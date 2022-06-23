import logging
from datetime import datetime
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import sqlContext, SparkTableStorageFormat
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("update_clean_staging_subpartitions_values_table.")

parser = ArgumentParser(description="update_clean_staging_subpartitions_values_table")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("source_table_name")
parser.add_argument("--subpartitions", nargs="+", dest="subpartitions", required=False)

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_table_name = args.source_table_name
    subpartitions = args.subpartitions

    logger.info(
        "m=__main__, date={}, source={}, source_table_name={}, "
        ", msg=Job started".format(
            execution_date, source, source_table_name, subpartitions
        )
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()

    # create daily unique subpartitions values table
    df = (
        sqlContext.table(
            "{}.{}".format(db_info["db_clean_databricks"], source_table_name)
        )
        .selectExpr(*subpartitions)
        .where("year = {} and month = {} and day = {}".format(year, month, day))
        .distinct()
    )

    table_name = "subpartitions_values"
    database_name = db_info["db_clean_staging_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_staging_path"]
    # create database if not exists
    metastore_service.create_database(database_name)

    # this spark job only saves the files in S3, it does not call SparkMetastoreLoader to update metastore
    # it is the same behaviour as before S3Loader refactoring
    s3_loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
    )

    metastore_service.refresh_table(db_info["db_clean_staging_databricks"], table_name)
