from argparse import ArgumentParser
from datetime import date

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.services import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from typing import List

def load_from_s3(path: str) -> DataFrame:
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    return s3_consumer.get_data_from_file(
        path=path,
        format="parquet",
    )


def save_to_datalake(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    table_name: str,
    source: str,
) -> None:
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=dataframe,
        s3_path=f"{database_location}{table_name}",
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        compression="gzip",
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=database_location,
        force_recreate=True,
    )
    full_raw_table_name = f"datalake_{source}_raw.{table_name}"
    table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)
    if (
            table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
    ):
        table_privileges.apply()

    spark_metastore_service.refresh_table(database_name, table_name)


def transform_data(
    dataframe: DataFrame,
    timestamp_ntz_fields: List[str] = []
) -> DataFrame:
    df = dataframe.withColumn("dt_load", F.lit(date.today()))
    
    for field in timestamp_ntz_fields:
        if field in df.columns:
            df = df.withColumn(field, F.col(field).cast("timestamp"))
    
    return df

if __name__ == "__main__":
    parser = ArgumentParser(description="Load Idactum raw data")
    parser.add_argument("env", help="Forno/Prod values")
    parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("execution_date", help="DAG execution_date")
    parser.add_argument("source", help="Source name(e.g., idactum_houses)")
    parser.add_argument("timestamp_ntz_fields", help="Timestamp NTZ field names split by comma.")

    args = parser.parse_args()
    source = args.source

    config_service = ConfigurationService(source)
    s3_ingestion_path = config_service.get_config("s3_ingestion_path")

    timestamp_ntz_fields_list = []
    if args.timestamp_ntz_fields:
        timestamp_ntz_fields_list = [
            field.strip() for field in args.timestamp_ntz_fields.split(",") if field.strip()
        ]
    dataframe_to_save = transform_data(load_from_s3(path=s3_ingestion_path), timestamp_ntz_fields_list)

    save_to_datalake(
        dataframe=dataframe_to_save,
        environment=args.env,
        datalake_bucket=args.datalake_bucket,
        table_name=args.table_name,
        source=source,
    )