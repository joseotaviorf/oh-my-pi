import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql import functions as F
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
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_ifrs_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)


def _load_raw_data(
    spark_client,
    df,
    environment,
    source,
    datalake_bucket,
    table_name,
    partition_cols,
    target_database_name=None,
    target_table_name=None,
):
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

    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )
    spark_metastore_service.create_database(write_database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

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
    )
    # Unpartitioned tables (extraction_type: full) would emit an empty
    # ALTER TABLE ... ADD PARTITION ( ), which Spark rejects with a ParseException.
    if partition_cols:
        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            partition_cols=partition_cols,
        )


def _read_incremental(
    s3_consumer, source_root_path, format, load_start_date, load_end_date
):
    dt_start = datetime.strptime(load_start_date, "%Y-%m-%d").date()
    dt_end = datetime.strptime(load_end_date, "%Y-%m-%d").date()
    if dt_start > dt_end:
        raise ValueError(
            f"load_start_date ({load_start_date}) must be <= load_end_date ({load_end_date})"
        )

    source_path = source_root_path.rstrip("/")
    logger.info(
        f"m=_read_incremental, path={source_path}, "
        f"msg=Reading period [{load_start_date}, {load_end_date}]..."
    )
    df = s3_consumer.get_data_from_file(source_path, format)
    # Push the date window down onto the year/month/day partition columns so Delta
    # prunes partitions instead of scanning the whole table.
    return df.filter(
        F.expr(
            "make_date(year, month, day) "
            f"BETWEEN date('{load_start_date}') AND date('{load_end_date}')"
        )
    )


def _read_full_snapshot(s3_consumer, source_root_path, format):
    source_path = source_root_path.rstrip("/")
    logger.info(f"m=_read_full_snapshot, msg=Reading from {source_path}...")
    return s3_consumer.get_data_from_file(source_path, format)


def _ensure_partition_columns(df, partition_cols):
    if not partition_cols:
        return df

    if all(col_name in df.columns for col_name in partition_cols):
        return df

    if "timestamp" in df.columns:
        return (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column("timestamp")
            .output()
        )

    raise ValueError(
        f"Partition columns {partition_cols} missing and no timestamp column to derive them"
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source DAG")
    parser.add_argument(
        "load_start_date",
        help="Start date (inclusive) for the period to ingest. Format: '%Y-%m-%d'",
    )
    parser.add_argument(
        "load_end_date",
        help="End date (inclusive) for the period to ingest. Format: '%Y-%m-%d'",
    )
    parser.add_argument("table_name", help="name of the output table")
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name

    config_service = ConfigurationService(source)
    table_config = config_service.get_config(table_name)
    source_root_path = table_config["source_root_path"]
    format = table_config["format"]
    partition_cols = table_config.get("partition_cols", [])
    extraction_type = table_config.get("extraction_type", "incremental")

    logger.info(
        f"""
            m=__main__, environment={environment}, source={source},
            datalake_bucket={datalake_bucket}, source_root_path={source_root_path},
            load_start_date={load_start_date}, load_end_date={load_end_date},
            table_name={table_name}, extraction_type={extraction_type},
            partition_cols={partition_cols}, msg=Starting spark job...
        """
    )

    s3_consumer = S3Consumer(spark_client)

    if extraction_type == "full" or not partition_cols:
        df = _read_full_snapshot(s3_consumer, source_root_path, format)
    else:
        df = _read_incremental(
            s3_consumer,
            source_root_path,
            format,
            load_start_date,
            load_end_date,
        )

    df = _ensure_partition_columns(df, partition_cols)

    if df.rdd.isEmpty():
        logger.warning(
            f"m=__main__, table_name={table_name}, load_start_date={load_start_date}, "
            f"load_end_date={load_end_date}, extraction_type={extraction_type}, "
            f"msg=No data found for the requested window. Skipping load."
        )
    else:
        _load_raw_data(
            spark_client,
            df,
            environment,
            source,
            datalake_bucket,
            table_name,
            partition_cols,
            target_database_name=args.target_database_name,
            target_table_name=args.target_table_name,
        )
