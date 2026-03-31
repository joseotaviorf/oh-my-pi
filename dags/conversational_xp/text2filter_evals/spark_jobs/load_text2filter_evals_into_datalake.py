import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from pyspark.sql import functions as F

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_text2filter_evals_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _get_forno_source_path(environment: str, source: str) -> str:
    if environment == "forno":
        return source.replace(
            "s3://data-science.s3.data", "s3://data-science.s3.forno.data"
        )
    return source


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="root S3 path to the parquet source")
    parser.add_argument(
        "date_to_ingest",
        help="Date to be used in filtering the files. Format: '%%Y-%%m-%%d'",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("partitions", help="list with partition cols")
    parser.add_argument("format", help="data format to load from S3")

    args = parser.parse_args()
    environment = args.environment
    bucket = args.bucket
    source = args.source
    source_root_path = _get_forno_source_path(environment, args.source_root_path)
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))
    data_format = args.format

    logger.info(
        f"m=main, environment={environment}, source={source}, "
        f"source_root_path={source_root_path}, date_to_ingest={date_to_ingest}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=main, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    dt_execution = datetime.strptime(date_to_ingest, "%Y-%m-%d")
    full_source_path = (
        f"{source_root_path}/"
        f"year={dt_execution.year}/"
        f"month={dt_execution.month}/"
        f"day={dt_execution.day}/"
    )

    logger.info(f"m=main, msg=Reading parquet from {full_source_path}")

    df = s3_consumer.get_data_from_file(full_source_path, data_format)

    df = (
        df.withColumn("year", F.lit(dt_execution.year))
        .withColumn("month", F.lit(dt_execution.month))
        .withColumn("day", F.lit(dt_execution.day))
    )

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partition_cols,
    )

    logger.info(f"m=main, msg=Successfully loaded {table_name} into datalake")


if __name__ == "__main__":
    main()
