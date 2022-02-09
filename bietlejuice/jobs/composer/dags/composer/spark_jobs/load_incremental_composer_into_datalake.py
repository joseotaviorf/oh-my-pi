import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_composer_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("context", help="context of the DAG")
    parser.add_argument("table_name", help="table name for data catalog")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, context={args.context}
            execution_date={args.execution_date}, datalake_bucket={args.datalake_bucket},
            table_name={args.table_name}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    context = args.context
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    table_name = args.table_name
    partition_cols = ["year", "month", "day"]

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    db_info = DatalakeMetastoreService.get_db_info(
        environment, context, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(db_info["db_raw_databricks"])
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    df = s3_consumer.get_data_from_file(
        path=f"{database_location}{table_name}/year={dt_execution.year}/month={dt_execution.month}/day={dt_execution.day}/",
        format="json",
    )

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(dt_execution)
        .output()
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
