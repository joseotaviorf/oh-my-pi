import ast
import logging
import re
from argparse import ArgumentParser
from datetime import date, datetime, timedelta
from typing import List, Optional, Set

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_clustering_image_model_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

# Matchmaker writes one folder per UTC processing day: .../results/YYYY-MM-DD/
ISO_DATE_DIR = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Parquet may use listing_id_* (Matchmaker) or legacy sourcenameid_* names
MATCHMAKER_COLUMN_RENAMES = (
    ("listing_id_anchor", "sourcenameid_anchor"),
    ("listing_id_pair", "sourcenameid_pair"),
)


def _fs_entry_is_directory(entry) -> bool:
    """Compatible with Databricks FileInfo (isDir method or boolean)."""
    is_dir = getattr(entry, "isDir", None)
    if callable(is_dir):
        return bool(is_dir())
    return bool(is_dir)


def parse_folder_date(folder_name: str) -> Optional[date]:
    """Return date if folder_name is YYYY-MM-DD, else None."""
    name = folder_name.rstrip("/")
    if not ISO_DATE_DIR.match(name):
        return None
    return datetime.strptime(name, "%Y-%m-%d").date()


def normalize_matchmaker_columns(df: DataFrame) -> DataFrame:
    """Align Matchmaker parquet names with historical raw column names."""
    out = df
    for old, new in MATCHMAKER_COLUMN_RENAMES:
        if old in out.columns and new not in out.columns:
            out = out.withColumnRenamed(old, new)
    return out


def read_dated_partition_parquet(
    spark: SparkSession,
    read_path: str,
    dt_model: date,
) -> Optional[DataFrame]:
    """
    Read all parquet under a dated S3 folder (Matchmaker append layout).
    """
    try:
        logger.info(
            "m=read_dated_partition_parquet, "
            f"msg=Reading parquet from {read_path}, dt_model={dt_model}."
        )
        df = spark.read.format("parquet").load(path=read_path)
        df = normalize_matchmaker_columns(df)
        row_count = df.count()
        logger.info(
            "m=read_dated_partition_parquet, "
            f"msg=Loaded {row_count} rows, columns={len(df.columns)} from {read_path}."
        )
        if row_count == 0:
            return None
        df = (
            df.withColumn("dt_model", lit(dt_model))
            .withColumn("year", lit(dt_model.year))
            .withColumn("month", lit(dt_model.month))
            .withColumn("day", lit(dt_model.day))
        )
        return df
    except Exception as e:
        logger.error(
            "m=read_dated_partition_parquet, "
            f"msg=Error reading parquet from {read_path}. Exception: {e}."
        )
        return None


def load_dataframe_into_datalake(
    datalake_bucket: str,
    df: DataFrame,
    environment: str,
    partition_cols: List[str],
    raw_table_name: str,
    source: str,
    target_database_name: str = None,
    target_table_name: str = None,
) -> None:
    """
    Loads a spark dataframe into the datalake.
    """
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(
        env=environment,
        source=source,
        bucket=datalake_bucket,
    )

    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=raw_table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=target_database_name,
            target_table=target_table_name,
        )
    )
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    spark_metastore_service.create_database(write_database_name)

    s3_loader.load_df(
        df=df,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=partition_cols,
        max_records_per_file=250000,
        compression="gzip",
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


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="Forno/Prod values")
    parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
    parser.add_argument("source", help="DAG name")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument(
        "base_path", help="S3 prefix containing YYYY-MM-DD dated folders"
    )
    parser.add_argument("load_start_date", help="Start date to load data")
    parser.add_argument("load_end_date", help="End date to load data")

    add_validation_target_args(parser)
    return parser.parse_args()


def main():
    args = parse_arguments()

    environment: str = args.environment
    datalake_bucket: str = args.datalake_bucket
    source: str = args.source
    raw_table_name: str = args.table_name
    partition_cols: List[str] = ast.literal_eval(args.partitions)
    base_path: str = args.base_path.rstrip("/") + "/"
    load_start_date: date = datetime.strptime(args.load_start_date, "%Y-%m-%d").date()
    load_end_date: date = datetime.strptime(args.load_end_date, "%Y-%m-%d").date()

    range_dates: List[date] = [
        load_start_date + timedelta(days=x)
        for x in range((load_end_date - load_start_date).days + 1)
    ]
    range_set: Set[date] = set(range_dates)

    logger.info(
        "m=main, "
        f"environment={environment}, datalake_bucket={datalake_bucket}, "
        f"source={source}, raw_table_name={raw_table_name}, "
        f"partition_cols={partition_cols}, base_path={base_path}, "
        f"load_start_date={load_start_date}, load_end_date={load_end_date}. "
        "msg=Starting Spark Job..."
    )

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    if dbutils is None:
        raise RuntimeError("dbutils is required to list dated folders on S3.")

    spark = SparkSession.builder.getOrCreate()

    for entry in dbutils.fs.ls(base_path):
        if not _fs_entry_is_directory(entry):
            continue
        folder_label = (entry.name or "").rstrip("/")
        if not folder_label:
            folder_label = entry.path.rstrip("/").split("/")[-1]
        dt_folder = parse_folder_date(folder_label)
        if dt_folder is None or dt_folder not in range_set:
            continue

        read_path = entry.path
        if not read_path.endswith("/"):
            read_path = read_path + "/"

        df_model = read_dated_partition_parquet(
            spark=spark,
            read_path=read_path,
            dt_model=dt_folder,
        )
        if df_model is not None:
            load_dataframe_into_datalake(
                df=df_model,
                datalake_bucket=datalake_bucket,
                environment=environment,
                partition_cols=partition_cols,
                raw_table_name=raw_table_name,
                source=source,
                target_database_name=args.target_database_name,
                target_table_name=args.target_table_name,
            )
        else:
            logger.info(
                f"m=main, msg=No parquet data loaded for dated folder {read_path}."
            )


if __name__ == "__main__":
    main()
