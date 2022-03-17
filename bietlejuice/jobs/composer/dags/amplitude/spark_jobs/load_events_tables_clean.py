import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load-events-tables-clean")

parser = ArgumentParser(description="load-events-tables-clean")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)


if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    partition_cols = args.partition_by

    logger.info(
        "m=__main__, date={}, source={}, msg=Job started".format(execution_date, source)
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d") - timedelta(days=1)
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    database_name = db_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]

    incremental_tables = FileService.list_files(QUERIES_DATALAKE_PATH + source + "/clean")
    incremental_tables = [table_name.replace(".sql") for table_name in incremental_tables]
    
    for table_name in incremental_tables:
        query_path = QUERIES_DATALAKE_PATH + source + "/{}.sql".format(table_name)
        query = FileService.get_query_from_file_name(query_path).format(
            year=year, month=month, day=day
        )

        # create df
        df = spark_client.get_records(query)
        df = SparkDataFrameService(df).optimize_partition(250000).output()

        # load df
        # this spark job only saves the files in S3
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
            database_location=database_location,
        )
        spark_metastore_loader.update_metastore(
            df, database_name, table_name, format_options, database_location, partition_cols
        )
