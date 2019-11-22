import logging
from datetime import datetime
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import (
    spark,
    sqlContext,
    SparkMetastoreService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("update_clean_staging_subpartitions_values_table.")

parser = ArgumentParser(description="update_clean_staging_subpartitions_values_table")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("source")
parser.add_argument("source_table_name")
parser.add_argument("--subpartitions", nargs="+", dest="subpartitions", required=False)

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    source = args.source
    source_table_name = args.source_table_name
    subpartitions = args.subpartitions

    logger.info(
        "m=__main__, date={}, source={}, source_table_name={}, "
        "target_table_name={}, msg=Job started".format(
            execution_date, source, source_table_name, subpartitions
        )
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    spark_metastore_service = SparkMetastoreService(
        db_info["db_clean_staging_databricks"],
        db_info["db_clean_staging_path"],
        spark_sql_client,
    )
    loader = S3Loader(spark_metastore_service)

    # create daily unique subpartitions values table
    spark_metastore_service.create_database()  # if not exists
    df = (
        sqlContext.table(
            "{}.{}".format(db_info["db_clean_databricks"], source_table_name)
        )
        .selectExpr(*subpartitions)
        .where("year = {} and month = {} and day = {}".format(year, month, day))
        .distinct()
    )

    loader.load_full_table(
        df, "subpartitions_values", SparkTableStorageFormat.DEFAULT_CLEAN
    )
