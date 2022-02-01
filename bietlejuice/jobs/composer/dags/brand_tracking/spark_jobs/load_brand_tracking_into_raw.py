from argparse import ArgumentParser
from pyspark.sql.functions import lit, expr

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_brand_tracking_into_raw"

logger = QuintoAndarLogger(JOB_NAME)


def __columns_to_alphanumeric_snake_case(df):
    old_columns = df.columns
    new_columns = [
        StringFormatter.set_alphanumeric_snake_case(column) for column in old_columns
    ]
    return df.toDF(*new_columns)


def __get_unpivoted_table(df, ignore_cols_list=[]):
    all_columns = """"""
    for col in df.columns:
        if col not in ignore_cols_list:
            all_columns += f"""'{col}',{col},"""

    stack = f"stack({len(df.columns) - len(ignore_cols_list)}, {all_columns[:-1]}) as (id_question, answer)"

    return df.select("respondent_serial", "wave", "year", "quarter", expr(stack))


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("year_previous_quarter")
    parser.add_argument("previous_quarter")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    year_previous_quarter = args.year_previous_quarter
    previous_quarter = args.previous_quarter

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    brand_tracking_bucket = config_service.get_config("brand_tracking_bucket")
    ignore_cols_list = config_service.get_config("ignore_cols_list")
    file_to_ingest_base_path = config_service.get_config("file_to_ingest_base_path")
    file_to_ingest_prefix = config_service.get_config("file_to_ingest_prefix")

    logger.info(
        f"""m=__main__, environment={env}, source={source}, datalake_bucket={datalake_bucket},
        table_name={table_name}, msg=Starting spark job..."""
    )

    spark_client = SparkClient()
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    df = (
        spark_client.conn.read.option("header", "true")
        .option("multiLine", "true")
        .option("quote", '"')
        .option("escape", '"')
        .option("basePath", f"s3://{brand_tracking_bucket}/{file_to_ingest_base_path}")
        .csv(
            f"s3://{brand_tracking_bucket}/{file_to_ingest_base_path}{file_to_ingest_prefix}{year_previous_quarter}q{previous_quarter}.csv"
        )
        .withColumn("year", lit(year_previous_quarter))
        .withColumn("quarter", lit(previous_quarter))
    )

    df = __columns_to_alphanumeric_snake_case(df)

    if (
        table_name.find("unpivoted") >= 0
    ):  # if table name contains the word unpivoted, table should be unpivoted
        df = __get_unpivoted_table(df, ignore_cols_list)

    s3_loader.load_df(
        df=df,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        s3_path=f"{database_location}{table_name}",
        partitions=raw_partition_cols,
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=database_location,
        partitions=raw_partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=table_name,
        partition_cols=raw_partition_cols,
    )
