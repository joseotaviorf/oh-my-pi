import ast
import logging

from argparse import ArgumentParser
from datetime import datetime, date
from typing import List

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.services import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from quintoandar_logger import QuintoAndarLogger

SOURCE = "iptu_poa"
JOB_NAME = f"load_{SOURCE}_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def load_from_s3(base_path: str, year: int) -> DataFrame:
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    return s3_consumer.get_data_from_file(
        options={"multiline": "false"},
        path=f"s3://{base_path}/{year}/iptu_poa_raw_all.jsonl.gz",
        format="json",
    )


def save_to_datalake(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    table_name: str,
    partitions: List[str]
) -> None:
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=dataframe,
        s3_path=f"{database_location}{table_name}",
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=partitions,
        compression="gzip",
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=database_location,
        partitions=partitions,
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partitions,
    )


def transform_data(dataframe: DataFrame) -> DataFrame:
    return (
        dataframe
        .select("response.*")
        .withColumn("dt_load", F.lit(date.today()))
        .withColumn("year", F.col("ano_exercicio"))
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", help="Forno/Prod values")
    parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("execution_date", help="DAG execution_date")

    args = parser.parse_args()

    config_service = ConfigurationService(SOURCE)
    base_s3_ingestion_path = config_service.get_config("base_s3_ingestion_path")

    partition_year = datetime.strptime(args.execution_date, "%Y-%m-%d").year
    dataframe_to_save = transform_data(load_from_s3(base_path=base_s3_ingestion_path, year=partition_year))

    save_to_datalake(
        dataframe=dataframe_to_save,
        environment=args.env,
        datalake_bucket=args.datalake_bucket,
        table_name=args.table_name,
        partitions=ast.literal_eval(args.partitions),
    )
