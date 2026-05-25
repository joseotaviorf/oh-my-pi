import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_batch_inference_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument(
        "date_to_ingest",
        help="Date to be used in filtering the files. Format: '%Y-%m-%d'",
    )

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    date_to_ingest = args.date_to_ingest

    config_service = ConfigurationService(source)

    raw_partition_cols = config_service.get_config("partition_cols")
    format = config_service.get_config("format")
    source_root_path = config_service.get_config("source_root_path")
    table_name = config_service.get_config("table_name")

    logger.info(
        f"""
            m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
            source_root_path={source_root_path}, date_to_ingest={date_to_ingest}, table_name={table_name},
            msg=Starting spark job...
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

    dt_execution = datetime.strptime(date_to_ingest, "%Y-%m-%d")
    df = s3_consumer.get_data_from_file(
        f"{source_root_path}/year={dt_execution.year}/month={dt_execution.month}/day={dt_execution.day}/",
        format,
    )

    path = f"{database_location}{table_name}"
    logger.info(f"m=__main__, msg=Loading data into {path}...")

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("timestamp")
        .output()
    )

    (
        df.write.format("parquet")
        .mode("overwrite")
        .option("path", path)
        .partitionBy(raw_partition_cols)
        .saveAsTable(database_name + "." + table_name)
    )


if __name__ == "__main__":
    main()
