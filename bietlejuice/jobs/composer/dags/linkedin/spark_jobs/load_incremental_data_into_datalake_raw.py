import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from quintoandar_linkedin_client.linkedin_consumer import LinkedInConsumer

from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("media", help="name of the media")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("auth", help="id, secret  and refresh token for api call")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, media={args.media},
            execution_date={args.execution_date}, datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    source = args.source
    media = args.media
    datalake_bucket = args.datalake_bucket
    auth = json.loads(args.auth)
    execution_date = args.execution_date
    partition_cols = ["acc", "year", "month", "day"]

    spark_client = SparkClient()
    linkedin_consumer = LinkedInConsumer(datalake_bucket, execution_date, auth)
    data = linkedin_consumer.get_data()
    if data:
        for data_type in data:
            stats = data[data_type]
            if stats:
                try:
                    schema = linkedin_consumer.get_schema(data_type)
                    df = spark_client.create_dataframe(stats)
                    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
                    df = df.coalesce(1)
                    df = (
                        SparkDataFrameService()
                        .input(df)
                        .create_year_month_day_columns_from_date(dt_execution)
                        .output()
                    )

                    datalake_info = DatalakeMetastoreService.get_db_info(
                        environment, source, datalake_bucket
                    )
                    spark_metastore_service = SparkMetastoreService(spark_client)
                    database_name = datalake_info["db_raw_databricks"]
                    spark_metastore_service.create_database(database_name)

                    database_location = datalake_info["db_raw_path"]
                    format_options = SparkTableStorageFormat.DEFAULT_RAW
                    table_name = f"{media}_{data_type}"

                    # loaders
                    s3_loader = S3Loader()
                    spark_metastore_loader = SparkMetastoreLoader(
                        spark_metastore_service
                    )
                    s3_loader.load_df(
                        df=df,
                        s3_path=f"{database_location}{table_name}",
                        format_options=format_options,
                        partitions=partition_cols,
                    )
                    spark_metastore_loader.update_metastore(
                        df,
                        database_name,
                        table_name,
                        format_options,
                        database_location,
                        partition_cols,
                        force_recreate=False,
                    )
                    spark_metastore_service.create_new_partitions_from_df(
                        database_name=database_name,
                        table_name=table_name,
                        df=df,
                        partition_cols=partition_cols,
                    )
                    spark_metastore_service.refresh_table(database_name, table_name)
                except Exception as e:
                    logger.error(f"table={data_type}, e={e}")
