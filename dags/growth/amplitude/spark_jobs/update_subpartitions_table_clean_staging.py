from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat, sqlContext
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "update_subpartitions_table_clean_staging"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("table_name")
parser.add_argument("--subpartitions", nargs="+", dest="subpartitions", required=False)

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    subpartitions = args.subpartitions

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"table_name{table_name}, subpartitions={subpartitions}, msg=Job started"
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_clean_name = db_info["db_clean_databricks"]
    db_clean_staging_name = db_info["db_clean_staging_databricks"]
    db_clean_staging_path = db_info["db_clean_staging_path"]

    df = (
        sqlContext.table(f"{db_clean_name}.{table_name}")
        .selectExpr(*subpartitions)
        .where(f"year = {year} and month = {month} and day = {day}")
        .distinct()
    )

    subpartitions_table_name = "subpartitions_values"

    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN

    metastore_service.create_database(db_clean_staging_name)
    s3_loader = S3Loader()
    s3_loader.load_full_table(
        df=df,
        database_name=db_clean_staging_name,
        table_name=subpartitions_table_name,
        format_options=format_options,
        database_location=db_clean_staging_path,
    )

    metastore_service.refresh_table(db_clean_staging_name, subpartitions_table_name)
