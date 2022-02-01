import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_crawler_listings_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("context")
    parser.add_argument("table_name")
    parser.add_argument("origin", type=str, help="Name of crawled source")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context
    table_name = args.table_name
    origin = args.origin
    execution_date_str = args.execution_date

    config_service = ConfigurationService(
        source, intermediate_path=f"{source}/{context}/spark_jobs"
    )
    source_root_path = config_service.get_config("root_path")
    job_extra_args = config_service.get_config("job_extra_args")
    consumer_extra_args = job_extra_args.get("consumer")
    custom_records_per_file = job_extra_args.get("custom_records_per_file")
    partitions = config_service.get_config("partition_cols")

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, context = {context},datalake_bucket={datalake_bucket}, origin={origin},
                source_root_path={source_root_path}, table_name={table_name}, execution_date={execution_date_str} msg=Starting spark job...
        """
    )

    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    # Initializing clients
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    path = (
        source_root_path
        + f"origin={origin}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}/"
    )
    df = s3_consumer.get_data_from_file(path=path, **consumer_extra_args)
    df = (
        df.withColumn("year", lit(execution_date.year))
        .withColumn("month", lit(execution_date.month))
        .withColumn("day", lit(execution_date.day))
    )

    db_info = DatalakeMetastoreService.get_db_info(
        environment, f"{source}_{context}", datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partitions,
        max_records_per_file=custom_records_per_file.get(
            origin, s3_loader.MAX_RECORDS_PER_FILE
        ),
    )

    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions,
        force_recreate=False,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partitions,
    )
