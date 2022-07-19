"""
    This job intends to increment events tables that are on the clean layer.
    There are some tables with name like: {id_app}_{event_type}_events that sums
    up informations from events table by id_app and event_type with some extractions.

    Since amplitude updates its values every day, we need to load those clean tables
    in order to update its values.
"""

import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load-subpartitioned-event-tables-to-clean")

parser = ArgumentParser(description="load-subpartitioned-event-tables-to-clean")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)


if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    partition_cols = args.partition_by

    logger.info(
        "m=__main__, date={}, source={}, msg=Job started".format(execution_date, source)
    )

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    amplitude_clean_database_name = db_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]
    incremental_tables_queries = FileService.list_layer_sql_files(source, "clean")

    for table_name in incremental_tables_queries:
        table_name = table_name.replace(".sql", "")
        query_path = (
            QUERIES_DATALAKE_PATH + source + "/clean" + "/{}.sql".format(table_name)
        )
        query = FileService.get_query_from_file_name(query_path).format(
            execution_date.year, execution_date.month, execution_date.day
        )

        df = spark_client.get_records(query)
        df = SparkDataFrameService(df).optimize_partition(250000).output()

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
            database_location=database_location,
        )
        spark_metastore_loader.update_metastore(
            df,
            amplitude_clean_database_name,
            table_name,
            format_options,
            database_location,
            partition_cols,
        )
