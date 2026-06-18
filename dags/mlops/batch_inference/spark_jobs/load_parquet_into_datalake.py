import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_batch_inference_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def load_raw_data(
    df,
    environment,
    source,
    datalake_bucket,
    table_name,
    raw_partition_cols,
    target_database_name=None,
    target_table_name=None,
):
    spark_client = SparkClient()
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=target_database_name,
            target_table=target_table_name,
        )
    )
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(write_database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader.load_df(
        df=df,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=raw_partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=format_options,
        database_location=write_location,
        partitions=raw_partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        partition_cols=raw_partition_cols,
    )


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument(
        "date_to_ingest",
        help="Date to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    add_validation_target_args(parser)
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

    dt_execution = datetime.strptime(date_to_ingest, "%Y-%m-%d")
    df = s3_consumer.get_data_from_file(
        f"{source_root_path}/year={dt_execution.year}/month={dt_execution.month}/day={dt_execution.day}/",
        format,
    )

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("timestamp")
        .output()
    )

    load_raw_data(
        df,
        environment,
        source,
        datalake_bucket,
        table_name,
        raw_partition_cols,
        target_database_name=args.target_database_name,
        target_table_name=args.target_table_name,
    )


if __name__ == "__main__":
    main()
