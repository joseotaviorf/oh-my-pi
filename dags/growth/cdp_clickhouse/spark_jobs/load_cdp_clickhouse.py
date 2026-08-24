import json
import logging
import os
from argparse import ArgumentParser
from datetime import datetime, timedelta

import clickhouse_connect
from pyspark.sql import Window
from pyspark.sql.functions import col, current_timestamp, desc, row_number
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_cdp_clickhouse"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def trigger_insert_into_clickhouse_procedure(
    clickhouse_client,
    database_name: str,
    table_name: str,
    clickhouse_incremental_column: str,
    target_path: str,
    role_arn: str,
    start_time: str,
    end_time: str,
):
    """
    Dump ClickHouse rows to S3 Parquet staging files.

    Raw staging exports are partitioned by ingest hour
    (ingestion_date as yyyy-MM-dd-HH). event_name partitioning is applied later
    in clean Delta tables.
    """

    query = f"""
    INSERT INTO FUNCTION
        s3(
            '{target_path}',
            extra_credentials(
                role_arn = '{role_arn}'
            ),
            'Parquet'
        )
    PARTITION BY concat('ingestion_date=', ingestion_date)
    SELECT
        *,
        formatDateTime({clickhouse_incremental_column}, '%Y-%m-%d-%H') AS ingestion_date
    FROM {database_name}.{table_name}
    WHERE
        {clickhouse_incremental_column} >= '{start_time}'::TIMESTAMP
        AND {clickhouse_incremental_column} <= '{end_time}'::TIMESTAMP
    SETTINGS
        s3_truncate_on_insert = 1;
    """

    logger.info(f"writing data to s3, procedure={query}")

    clickhouse_client.command(query)

    logger.info("data dumped successfully!")


def _does_this_path_exist(spark_session, path: str) -> bool:
    """
    Check if the given S3 path exists.
    """
    hadoop_conf = spark_session.sparkContext._jsc.hadoopConfiguration()
    hadoop_path = spark_session.sparkContext._jvm.org.apache.hadoop.fs.Path(path)
    hadoop_fs = spark_session.sparkContext._jvm.org.apache.hadoop.fs.FileSystem.get(
        hadoop_path.toUri(), hadoop_conf
    )

    return hadoop_fs.exists(hadoop_path)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod environment")
    parser.add_argument("datalake_bucket", help="S3 bucket for the datalake")
    parser.add_argument("dag_name", help="DAG name for configuration lookup")
    parser.add_argument("schema", help="Metastore schema (custom_schema)")
    parser.add_argument("table_name", help="Destination datalake raw table name")
    parser.add_argument("extraction_type", help="full or incremental")
    parser.add_argument(
        "load_start_date",
        help="Inclusive start of the export window (YYYY-MM-DD HH:MM:SS).",
    )
    parser.add_argument(
        "load_end_date",
        help="Exclusive end of the export window (YYYY-MM-DD HH:MM:SS).",
    )
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    schema = args.schema
    table_name = args.table_name
    extraction_type = args.extraction_type

    load_start_date = datetime.fromisoformat(args.load_start_date).strftime(
        "%Y-%m-%d %H:%M:%S"
    )

    load_end_date = datetime.fromisoformat(args.load_end_date).strftime(
        "%Y-%m-%d %H:%M:%S"
    )

    os.environ["ENVIRONMENT"] = environment
    env_prefix = environment.upper()

    config = ConfigurationService(dag_name)
    table_config = config.get_config(table_name)

    clickhouse_host = config.get_config("clickhouse_host")
    clickhouse_http_port = config.get_config("clickhouse_http_port")
    clickhouse_database = config.get_config("clickhouse_database")
    clickhouse_incremental_column = config.get_config("clickhouse_incremental_column")
    clickhouse_source_table = table_config["clickhouse_source_table"]
    target_path = table_config["target_path"]
    source_path = table_config["source_path"]
    s3_export_role_arn = config.get_config("s3_export_role_arn")
    partition_columns = table_config["partition_columns"]

    logger.info(
        f"environment={environment}, "
        f"datalake_bucket={datalake_bucket}, "
        f"dag_name={dag_name}, "
        f"schema={schema}, "
        f"table_name={table_name}, "
        f"extraction_type={extraction_type}, "
        f"load_start_date={load_start_date}, "
        f"load_end_date={load_end_date}, "
        f"target_database_name={args.target_database_name}, "
        f"target_table_name={args.target_table_name}, "
        f"clickhouse_host={clickhouse_host}, "
        f"clickhouse_http_port={clickhouse_http_port}, "
        f"clickhouse_database={clickhouse_database}, "
        f"clickhouse_source_table={clickhouse_source_table}, "
        f"clickhouse_incremental_column={clickhouse_incremental_column}, "
        f"target_path={target_path}, "
        f"s3_export_role_arn={s3_export_role_arn}, "
        f"partition_columns={partition_columns}"
    )

    """
    Fetch login credentials.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    clickhouse_secret = json.loads(
        dbutils.secrets.get("cdp", "CLICKHOUSE_SERVICE_ACCOUNT")
    )
    clickhouse_user = clickhouse_secret[f"CLICKHOUSE_{env_prefix}_USERNAME"]
    clickhouse_password = clickhouse_secret[f"CLICKHOUSE_{env_prefix}_PASSWORD"]

    """
    Dump data into S3.
    """
    clickhouse_client = clickhouse_connect.get_client(
        host=clickhouse_host,
        port=clickhouse_http_port,
        username=clickhouse_user,
        password=clickhouse_password,
        database=clickhouse_database,
        secure=True,
        verify=False,
        connect_timeout=30,
        send_receive_timeout=600,
    )

    trigger_insert_into_clickhouse_procedure(
        clickhouse_client,
        clickhouse_database,
        clickhouse_source_table,
        clickhouse_incremental_column,
        target_path,
        s3_export_role_arn,
        load_start_date,
        load_end_date,
    )

    """
    Materialize raw table.
    """
    logger.info("loading data from s3...")
    scan_start = datetime.strptime(load_start_date, "%Y-%m-%d %H:%M:%S") - timedelta(
        hours=1
    )
    scan_end = datetime.strptime(load_end_date, "%Y-%m-%d %H:%M:%S") + timedelta(
        hours=1
    )

    spark_client = SparkClient()
    spark = spark_client.conn

    source_paths = []
    scan_hour = scan_start
    while scan_hour <= scan_end:
        ingestion_date_partition = scan_hour.strftime("%Y-%m-%d-%H")
        source_paths.append(
            f"{source_path.rstrip('/')}/ingestion_date={ingestion_date_partition}/data.parquet"
        )
        scan_hour += timedelta(hours=1)

    source_paths_filtered = [
        path for path in source_paths if _does_this_path_exist(spark, path)
    ]

    if not source_paths_filtered:
        raise FileNotFoundError(
            "No exported Parquet files were found for the requested load window."
        )

    df = spark.read.parquet(*source_paths_filtered)

    logger.info("data loaded successfully!")

    """
    Deduplicate raw events by id_event, application and event_name
    (latest ts_egw_updated_at).
    """
    dedup_window = Window.partitionBy("id_event", "application", "event_name").orderBy(
        desc("ts_egw_updated_at")
    )
    df = (
        df.withColumn("_rn", row_number().over(dedup_window))
        .filter(col("_rn") == 1)
        .drop("_rn")
    )
    logger.info(
        "raw events deduplicated by id_event, application, event_name "
        "(latest ts_egw_updated_at)"
    )

    df = df.withColumn("ts_load", current_timestamp())

    """
    Load data to datalake.
    """
    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
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
    format_options = "delta"

    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )
    spark_metastore_service.create_database(write_database_name)

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    s3_loader.load_df(
        df=df,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=partition_columns,
        optimize_dataframe=False,
    )

    """
    Update metastore.
    """
    spark_metastore_loader.update_metastore(
        df,
        write_database_name,
        write_table_name,
        format_options,
        write_location,
        partition_columns,
        force_recreate=False,
    )
