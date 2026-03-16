import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService
from pyspark.sql import functions as F

JOB_NAME = "load_batch_inference_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument(
        "load_start_date",
        help="Start date (inclusive) for the period to ingest. Format: '%Y-%m-%d'",
    )
    parser.add_argument(
        "load_end_date",
        help="End date (exclusive) for the period to ingest. Format: '%Y-%m-%d'",
    )

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    config_service = ConfigurationService(source)

    raw_partition_cols = config_service.get_config("partition_cols")
    format = config_service.get_config("format")
    source_root_path = config_service.get_config("source_root_path")
    table_name = config_service.get_config("table_name")
    model_name_filter = config_service.get_config("model_name_filter")

    logger.info(
        f"""
            m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
            source_root_path={source_root_path}, load_start_date={load_start_date}, load_end_date={load_end_date},
            table_name={table_name}, msg=Starting spark job...
        """
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    dt_start = datetime.strptime(load_start_date, "%Y-%m-%d").date()
    dt_end = datetime.strptime(load_end_date, "%Y-%m-%d").date()
    if dt_start > dt_end:
        raise ValueError(
            f"load_start_date ({load_start_date}) must be <= load_end_date ({load_end_date})"
        )

    dfs = []
    current = dt_start
    while current < dt_end:
        source_path = (
            f"{source_root_path}/year={current.year}/month={current.month}/day={current.day}/"
            f"model_name={model_name_filter}/"
        )
        logger.info(f"m=__main__, msg=Reading from {source_path}...")
        try:
            day_df = s3_consumer.get_data_from_file(source_path, format)
            day_df = (
                SparkDataFrameService()
                .input(day_df)
                .create_year_month_day_columns_from_dataframe_column("timestamp")
                .output()
            )
            day_df = day_df.withColumn("model_name", F.lit(model_name_filter))
            dfs.append(day_df)
        except Exception as e:
            logger.warning(
                f"m=__main__, path={source_path}, msg=Skipping day (no data or error): {e}"
            )
        current += timedelta(days=1)

    if not dfs:
        raise RuntimeError(
            f"No data found for period [{load_start_date}, {load_end_date})"
        )

    df = dfs[0]
    for next_df in dfs[1:]:
        df = df.unionByName(next_df, allowMissingColumns=True)

    path = f"{database_location}{table_name}"
    logger.info(f"m=__main__, msg=Loading data into {path}...")

    (
        df.write
        .format("parquet")
        .mode("overwrite")
        .option("path", path)
        .partitionBy(raw_partition_cols)
        .saveAsTable(database_name + "." + table_name)
    )


if __name__ == "__main__":
    main()
