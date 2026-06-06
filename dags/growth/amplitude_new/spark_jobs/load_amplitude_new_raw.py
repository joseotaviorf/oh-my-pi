import json
from argparse import ArgumentParser
from concurrent.futures import ThreadPoolExecutor

from pyspark.sql.functions import col, lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_amplitude_new_raw"
logger = QuintoAndarLogger(JOB_NAME)


def process_key(
    key,
    environment,
    source,
    datalake_bucket,
    execution_date,
    partition_cols,
    table_name,
    transient_location,
    transient_data_schema,
    transient_expected_cols,
    target_database_name: str = None,
    target_table_name: str = None,
):
    try:
        spark_client = SparkClient()
        dataframe_service = SparkDataFrameService()

        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        _, write_table_name, write_location = resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=target_database_name,
            target_table=target_table_name,
        )

        transient_path = (
            f"{transient_location}{key['app_id']}/{key['app_id']}_{execution_date}_*/"
        )
        logger.info(
            f"Starting events processing for app_id={key['app_id']}, path={transient_path}"
        )

        df = spark_client.conn.read.json(
            transient_path, schema=transient_data_schema
        ).filter(~col("event_type").contains("Exposure"))

        if not df.isEmpty():
            df = (
                dataframe_service.input(df)
                .format_column_names()
                .convert_struct_type_to_json()
                .create_columns_from_dict({"app": key["app_id"]})
                .create_year_month_day_columns_from_dataframe_column(
                    "server_upload_time"
                )
                .output()
            )

            missing_cols = [
                col for col in transient_expected_cols if col not in df.columns
            ]
            for table_col in missing_cols:
                df = df.withColumn(table_col, lit(None))

            df = df.select(transient_expected_cols).na.drop(subset=partition_cols)

            s3_loader = S3Loader()
            s3_loader.load_df(
                df=df,
                s3_path=f"{write_location}{write_table_name}",
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                partitions=partition_cols,
                optimize_dataframe=False,
            )
        else:
            logger.info(f"No events received from App ID {key['app_id']} for this day.")
    except Exception as error:
        logger.error(
            f"Failed to process events for App ID {key['app_id']}, error={error}"
        )


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    add_validation_target_args(parser)
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_arguments()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date
    config_service = ConfigurationService(source)
    partition_cols = config_service.get_config("raw_partition_cols")
    table_name = config_service.get_config("table_name")
    transient_location = config_service.get_config("transient_location")
    transient_data_schema = config_service.get_config("transient_data_schema")
    transient_expected_cols = config_service.get_config("transient_expected_cols")
    dbutils = BaseDBUtils().get_dbutils()
    all_keys = json.loads(dbutils.secrets.get("quintoandar", APIEnum.AMPLITUDE) or "[]")

    # Process keys in parallel
    with ThreadPoolExecutor() as executor:
        list(
            executor.map(
                lambda key: process_key(
                    key,
                    environment,
                    source,
                    datalake_bucket,
                    execution_date,
                    partition_cols,
                    table_name,
                    transient_location,
                    transient_data_schema,
                    transient_expected_cols,
                    args.target_database_name,
                    args.target_table_name,
                ),
                all_keys,
            )
        )
        print(f"Processed {len(all_keys)} keys.")
