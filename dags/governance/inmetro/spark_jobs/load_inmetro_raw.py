import ast
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from functools import reduce

from pyspark.sql.functions import input_file_name, regexp_extract, struct, to_json
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
    spark,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_inmetro_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _generate_date_range(start_date_str, end_date_str):
    start = datetime.strptime(start_date_str, "%Y-%m-%d")
    end = datetime.strptime(end_date_str, "%Y-%m-%d")
    if start > end:
        raise ValueError(
            f"load_start_date ({start_date_str}) must be <= load_end_date ({end_date_str})"
        )
    days = (end - start).days
    return [(start + timedelta(days=i)).strftime("%Y-%m-%d") for i in range(days + 1)]


def _load_single_date(
    target_date, serialize_columns_from_directory, partition_cols, inmetro_bucket
):
    file_path = f"{inmetro_bucket}/*/*/*/{bucket_directory}/{target_date}"
    path_attributes_pattern = (
        rf"{inmetro_bucket}/(\w+)/(\w+)/(\w+)/{bucket_directory}/{target_date}"
    )

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
            datetime.strptime(target_date, "%Y-%m-%d")
        )
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    return df


def get_inmetro_data(
    serialize_columns_from_directory, partition_cols, load_start_date, load_end_date
):
    dates = _generate_date_range(load_start_date, load_end_date)
    logger.info(f"m={JOB_NAME}, dates={dates}, msg=Loading date range")

    config_service = ConfigurationService(source)
    inmetro_bucket = config_service.get_config("inmetro_bucket")

    dfs = []
    for target_date in dates:
        try:
            df = _load_single_date(
                target_date,
                serialize_columns_from_directory,
                partition_cols,
                inmetro_bucket,
            )
            dfs.append(df)
            logger.info(f"m={JOB_NAME}, date={target_date}, msg=Loaded successfully")
        except Exception as e:
            logger.warning(
                f"m={JOB_NAME}, date={target_date}, msg=No data found, skipping. error={e}"
            )
            continue

    if not dfs:
        return None

    return reduce(lambda a, b: a.unionByName(b), dfs)


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
    parser.add_argument("load_end_date", nargs="?", default=None)
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date = args.execution_date
    partition_cols = ast.literal_eval(args.partition_cols)
    bucket_directory = args.bucket_directory
    serialize_columns_from_directory = ast.literal_eval(
        args.serialize_columns_from_directory
    )
    load_end_date = args.load_end_date or execution_date

    logger.info(
        f"""
        m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        table_name={table_name}, bucket_directory={bucket_directory}, partition_cols={partition_cols},
        load_start_date={execution_date}, load_end_date={load_end_date}, msg=Starting spark job...
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
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    df = get_inmetro_data(
        serialize_columns_from_directory, partition_cols, execution_date, load_end_date
    )

    if not df:
        logger.warning(
            f"m={JOB_NAME}, msg=There is no data currently available in the {bucket_directory} directory"
        )
    else:
        spark_metastore_service.create_database(write_database_name)

        s3_loader.load_df(
            df=df,
            s3_path=f"{write_location}{write_table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            format_options=format_options,
            database_location=write_location,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            partition_cols=partition_cols,
        )

        spark_metastore_service.refresh_table(write_database_name, write_table_name)
