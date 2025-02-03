from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.spark import (
    SparkDataFrameService,
    SparkTableStorageFormat,
    sqlContext,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_incremental_clean_staging"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("table_name")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_by = args.partition_by

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"table_name{table_name}, partition_by={partition_by}, msg=Job started"
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_clean_name = db_info["db_clean_databricks"]
    db_clean_staging_name = db_info["db_clean_staging_databricks"]
    db_clean_staging_path = db_info["db_clean_staging_path"]

    df = sqlContext.table(f"{db_clean_name}.{table_name}").where(
        f"year = {year} and month = {month} and day = {day}"
    )

    df_partitioned = (
        SparkDataFrameService(df)
        .optimize_partitions_by_partition_columns(partition_by)
        .output()
    )

    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    delta_loader = DeltaLoader()

    metastore_service.create_database(db_clean_staging_name)
    delta_loader.load_table(
        table_name=f"{db_clean_staging_name}.{table_name}",
        path=f"{db_clean_staging_path}{table_name}",
        source_df=df_partitioned,
        partition_by=partition_by,
    )
    metastore_service.refresh_table(db_clean_staging_name, table_name)
