import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_concierge_propensity_inference_scores_raw"
RUN_ID_PATH_PATTERN = r"concierge-propensity-model-batch/([^/]+)/"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _deduplicate_scores(df: DataFrame) -> DataFrame:
    """Keep one row per user/day/model_version when QuintoML retries leave multiple run_id folders."""
    dedup_window = Window.partitionBy(
        "id_user", "model_version", "year", "month", "day"
    ).orderBy(F.col("_metadata.file_modification_time").desc())

    return (
        df.withColumn("_source_path", F.input_file_name())
        .withColumn("_run_id", F.regexp_extract("_source_path", RUN_ID_PATH_PATTERN, 1))
        .withColumn("_row_number", F.row_number().over(dedup_window))
        .filter(F.col("_row_number") == 1)
        .drop("_row_number", "_source_path", "_run_id")
    )


def get_source_in_forno(environment, source):
    prod_string = "s3://quintoml-s3-data-quintoandar-com-br"
    forno_string = "s3://quintoml-s3-forno-data-quintoandar-com-br"
    if environment == "forno":
        return source.replace(prod_string, forno_string)
    return source


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source")
    parser.add_argument(
        "date_to_ingest",
        help="Date to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("raw_partition_cols", help="list with partition cols")
    parser.add_argument("format", help="data format to load from S3. ")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.bucket
    source = args.source
    source_root_path = get_source_in_forno(environment, args.source_root_path)
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    raw_partition_cols = json.loads(args.raw_partition_cols.replace("'", '"'))
    format = args.format

    logger.info(
        f"""
            m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
            source_root_path={source_root_path}, date_to_ingest={date_to_ingest}, table_name={table_name},
            msg=Starting spark job...
        """
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    dt_execution = datetime.strptime(date_to_ingest, "%Y-%m-%d")

    # QuintoML batch inference writes each run under a unique run_id folder:
    #   .../concierge-propensity-model-batch/{run_id}/year=.../month=.../day=.../model_version=.../
    # The glob over run_id is required to reach year=/month=/day=, but retries can leave
    # multiple run_id folders for the same day — deduplicate before writing to raw.
    source_root_path = source_root_path.rstrip("/")
    df = s3_consumer.get_data_from_file(
        f"{source_root_path}/*/year={dt_execution.year}/month={dt_execution.month}/day={dt_execution.day}/",
        format,
    )

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(dt_execution)
        .output()
    )

    total_rows = df.count()
    df = _deduplicate_scores(df)
    deduplicated_rows = df.count()
    if total_rows > deduplicated_rows:
        logger.warning(
            f"m=_deduplicate_scores, removed={total_rows - deduplicated_rows}, "
            f"original={total_rows}, after={deduplicated_rows}, "
            "msg=duplicate user scores removed across run_id folders"
        )

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=raw_partition_cols,
    )
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=raw_partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=table_name,
        partition_cols=raw_partition_cols,
    )


if __name__ == "__main__":
    main()
