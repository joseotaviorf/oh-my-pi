import logging
import ast

from argparse import ArgumentParser
from datetime import datetime
from pyspark.sql.functions import input_file_name, regexp_extract, to_json, struct

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
    BaseDBUtils,
    spark,
)


JOB_NAME = "load_inmetro_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_inmetro_data(serialize_columns_from_directory, partition_cols, execution_date):

    config_service = ConfigurationService(source)
    inmetro_bucket = config_service.get_config("inmetro_bucket")

    file_path = f"{inmetro_bucket}/*/*/*/{bucket_directory}/{execution_date}"
    path_attributes_pattern = (
        f"{inmetro_bucket}\/(\w+)\/(\w+)\/(\w+)\/{bucket_directory}/{execution_date}"
    )

    try:
        df = spark.read.format("json").load(file_path)

        if serialize_columns_from_directory:
            df = df.withColumn(
                "inmetro_info", to_json(struct([df[x] for x in df.columns]))
            ).select("inmetro_info")

        df = (
            df.withColumn(
                "repo", regexp_extract(input_file_name(), path_attributes_pattern, 1)
            )
            .withColumn(
                "database",
                regexp_extract(input_file_name(), path_attributes_pattern, 2),
            )
            .withColumn(
                "table", regexp_extract(input_file_name(), path_attributes_pattern, 3)
            )
        )

        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(
                datetime.strptime(execution_date, "%Y-%m-%d")
            )
            .optimize_partitions_by_partition_columns(partition_cols)
            .output()
        )

    except Exception as e:
        logger.error(f"m={JOB_NAME}, error={e}")
        return None

    return df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("partition_cols")
    parser.add_argument("bucket_directory")
    parser.add_argument("serialize_columns_from_directory")
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date = args.execution_date
    partition_cols = ast.literal_eval(args.partition_cols)
    bucket_directory = args.bucket_directory
    serialize_columns_from_directory = ast.literal_eval(args.serialize_columns_from_directory)

    logger.info(
        f"""
        m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        table_name={table_name}, bucket_directory={bucket_directory}, partition_cols={partition_cols},
        execution_date={execution_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]

    df = get_inmetro_data(serialize_columns_from_directory, partition_cols, execution_date)

    if not df:
        logger.warning(
            f"m={JOB_NAME}, msg=There is no data currently available in the {bucket_directory} directory"
        )
    else:
        spark_metastore_service.create_database(database_name)

        s3_loader.load_df(
            df=df,
            s3_path=database_location + table_name,
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=table_name,
            partition_cols=partition_cols,
        )

        spark_metastore_service.refresh_table(database_name, table_name)
