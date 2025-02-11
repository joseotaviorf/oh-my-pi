import logging
from argparse import ArgumentParser
import json

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from datetime import datetime, timedelta
import pyspark.sql.functions as F
from pyspark.sql.functions import regexp_extract


JOB_NAME = "load_copilot_judge_metrics_into_datalake"

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
    parser.add_argument("source_path", help="path to the parquet source")
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("partitions", help="list with partition cols")
    parser.add_argument("format", help="data format to load from S3. ")
    parser.add_argument(
        "execution_type",
        help="full to load all data, incremental to load only new data",
    )

    args = parser.parse_args()
    environment = args.environment
    bucket = args.bucket
    source = args.source
    source_path = _get_forno_source_path(
        environment=args.environment, source=args.source_path
    )
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))
    format = args.format
    execution_type = args.execution_type

    logger.info(
        f"m=__main__, environment={args.environment}, source={source}, table_name={table_name}, msg=Starting spark job..."
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(
        env=environment, source=source, bucket=bucket
    )

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info(
        f"m=__main__, msg=Creating database in Spark Metastore if it does not exist"
    )
    spark_metastore_service.create_database(database_name=db_info["db_raw_databricks"])
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    execution_date = "*"
    if execution_type == "incremental":
        execution_date = (datetime.now() - timedelta(1)).strftime("%Y-%m-%d")

    try:
        full_source_path = f"{source_path}/{execution_date}/metrics.parquet"
        judge_df = s3_consumer.get_data_from_file(path=full_source_path, format=format)
    except Exception as e:
        logger.error(
            f"""m=__main__, msg=Error while loading data into datalake, full source path {full_source_path}

            Exception={str(e)}"""
        )
        return

    judge_df = judge_df.withColumn(
        "date", regexp_extract(F.input_file_name(), r"(\d{4}-\d{2}-\d{2})", 1)
    )
    judge_df = (
        SparkDataFrameService()
        .input(judge_df)
        .create_year_month_day_columns_from_dataframe_column("date")
        .output()
    )

    s3_loader.load_df(
        df=judge_df,
        s3_path=f"{db_info['db_raw_path']}{table_name}",
        format_options=SparkTableStorageFormat.PARQUET,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=judge_df,
        database_name=db_info["db_raw_databricks"],
        table_name=table_name,
        format_options=SparkTableStorageFormat.PARQUET,
        database_location=db_info["db_raw_path"],
        partitions=partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=judge_df,
        database_name=db_info["db_raw_databricks"],
        table_name=table_name,
        partition_cols=partition_cols,
    )


if __name__ == "__main__":
    main()
