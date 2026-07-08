import json
import logging
import os
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql import Window
from pyspark.sql.functions import col, desc, lit, row_number
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_cdp_clickhouse"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod environment")
    parser.add_argument("datalake_bucket", help="S3 bucket for the datalake")
    parser.add_argument("dag_name", help="DAG name for configuration lookup")
    parser.add_argument("schema", help="Metastore schema (custom_schema)")
    parser.add_argument("table_name", help="Destination datalake raw table name")
    parser.add_argument("extraction_type", help="full or incremental")
    parser.add_argument("load_start_date", help="Load window start date (YYYY-MM-DD)")
    parser.add_argument(
        "load_end_date", help="Load window end date (YYYY-MM-DD, exclusive)"
    )
    parser.add_argument(
        "-tdn",
        "--target-database-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    parser.add_argument(
        "-ttn",
        "--target-table-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    args = parser.parse_args()
    os.environ["ENVIRONMENT"] = args.environment

    config_service = ConfigurationService(args.dag_name)
    clickhouse_host = config_service.get_config("clickhouse_host")
    clickhouse_protocol = config_service.get_config("clickhouse_protocol")
    clickhouse_http_port = config_service.get_config("clickhouse_http_port")
    clickhouse_ssl = config_service.get_config("clickhouse_ssl")
    clickhouse_ssl_mode = config_service.get_config("clickhouse_ssl_mode")
    clickhouse_database = config_service.get_config("clickhouse_database")
    clickhouse_source_table = config_service.get_config("clickhouse_source_table")
    clickhouse_incremental_column = config_service.get_config(
        "clickhouse_incremental_column"
    )
    partition_columns = config_service.get_config("partition_columns")

    dbutils = BaseDBUtils().get_dbutils()
    clickhouse_secret = json.loads(
        dbutils.secrets.get("cdp", "CLICKHOUSE_SERVICE_ACCOUNT")
    )
    env_prefix = args.environment.upper()
    clickhouse_user = clickhouse_secret[f"CLICKHOUSE_{env_prefix}_USERNAME"]
    clickhouse_password = clickhouse_secret[f"CLICKHOUSE_{env_prefix}_PASSWORD"]

    spark_client = SparkClient(app_name=JOB_NAME)

    load_start_ts = datetime.strptime(args.load_start_date, "%Y-%m-%d")
    load_end_ts = datetime.strptime(args.load_end_date, "%Y-%m-%d")
    logger.info(
        f"Reading from ClickHouse table {clickhouse_database}.{clickhouse_source_table} "
        f"at host {clickhouse_host} with pushed filters on "
        f"{clickhouse_incremental_column} in [{load_start_ts}, {load_end_ts})"
    )
    clickhouse_read_filter = (
        col(clickhouse_incremental_column) >= lit(load_start_ts)
    ) & (col(clickhouse_incremental_column) < lit(load_end_ts))

    df = spark_client.get_data_from_external_source(
        format="clickhouse",
        options={
            "host": clickhouse_host,
            "protocol": clickhouse_protocol,
            "http_port": str(clickhouse_http_port),
            "ssl": str(clickhouse_ssl).lower(),
            "ssl_mode": clickhouse_ssl_mode,
            "user": clickhouse_user,
            "password": clickhouse_password,
            "database": clickhouse_database,
            "table": clickhouse_source_table,
            "spark.clickhouse.client.queryTimeout": "600s",
            "spark.clickhouse.read.settings.socket_timeout": "600000",
            "spark.clickhouse.read.settings.receive_timeout": "600000",
            "spark.clickhouse.read.settings.send_timeout": "600000",
            "spark.clickhouse.read.settings.max_execution_time": "600",
        },
    ).filter(clickhouse_read_filter)

    db_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.schema, args.datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_table_name = args.table_name
    if args.target_database_name and args.target_table_name:
        database_name = args.target_database_name
        write_table_name = args.target_table_name

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("timestamp_dt")
        .output()
    )
    dedup_window = Window.partitionBy("event_id").orderBy(desc("egw_updated_at"))
    df = (
        df.withColumn("_rn", row_number().over(dedup_window))
        .filter(col("_rn") == 1)
        .drop("_rn")
    )

    full_table_name = f"{database_name}.{write_table_name}"
    table_s3_path = f"{database_location}{write_table_name}"

    logger.info(f"Writing Delta raw table {full_table_name} at {table_s3_path}")
    DeltaLoader().load_table(
        table_name=full_table_name,
        path=table_s3_path,
        source_df=df,
        partition_by=partition_columns,
        merge_on=["event_id", "year", "month", "day"],
        when_matched_update_condition="source.egw_updated_at >= target.egw_updated_at",
    )

    logger.info(f"Done. Loaded rows into Delta table {full_table_name}")
