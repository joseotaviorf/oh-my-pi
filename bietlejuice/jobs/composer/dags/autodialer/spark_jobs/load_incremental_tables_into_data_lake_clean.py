import logging
import sys

from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)

from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "create_clean_incremental_table_in_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("table_name")
    parser.add_argument("env")
    parser.add_argument("data_lake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    args = parser.parse_args()

    table_name = args.table_name
    env = args.env
    data_lake_bucket = args.data_lake_bucket
    source = args.source
    execution_date = args.execution_date

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
        ]
    )
    partition_cols = list(partitions.keys())

    spark_client = SparkClient()
    db_info = DatalakeMetastoreService.get_db_info(env, source, data_lake_bucket)
    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)

    query_path = f"{QUERIES_DATALAKE_PATH}{source}/clean/{table_name}.sql"
    raw_to_clean_query = FileService.get_query_from_file_name(query_path)

    clean_df = databricks_consumer.get_data_from_query(
        raw_to_clean_query.format(**partitions)
    )

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(db_info["db_clean_databricks"])

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    if clean_df is None:
        logger.warning(
            f"m=__main__, execution_date={execution_date} msg=no incremental "
            f"data to process for this day"
        )
        sys.exit()

    clean_df = (
        SparkDataFrameService()
        .input(clean_df)
        .optimize_partition(10000)
        .create_columns_from_dict(partitions)
        .output()
    )
    database_name = db_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]
    s3_loader.load_incremental_table(
        df=clean_df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partition_cols=partition_cols,
    )
    spark_metastore_loader.save_as_table(
        clean_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
        schema_merging=True,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=clean_df,
        partition_cols=partition_cols,
    )

    spark_metastore_service.refresh_table(database_name, table_name)
