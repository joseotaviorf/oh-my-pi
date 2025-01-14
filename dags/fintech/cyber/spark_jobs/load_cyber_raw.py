import ast
import json
import logging
from argparse import ArgumentParser

from pyspark.sql.functions import col, current_timestamp, greatest, to_date

from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import OracleSparkConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.pipeline import FullTableLoaderPipeline, IncrementalTableLoaderPipeline
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger



JOB_NAME = "load_cyber_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _get_conn_config(dbutils, dbutils_secret_key):
      conn_config_json = dbutils.secrets.get(
          scope="quintoandar", key=dbutils_secret_key
      )

      return json.loads(conn_config_json)


def _send_warning(dbutils, environment, table_name):
    if environment == 'prod':
        key = GchatWebhooksEnum.FINTECH_ALERTS_PROD
    else:
        key = GchatWebhooksEnum.AE_ALERTS_FORNO

    gchat_webhook = dbutils.secrets.get(
        scope="quintoandar", key=key
    )

    message_content = (
        f"⚠️\n"
        f"DAG: *Cyber*\n"
        f"Environment: *{environment}*\n"
        f"Table: `{table_name}`\n"
        f"Status: *FAILED*\n"
        f"Error: *There is no data in Oracle database for table {table_name}*\n"
    )

    message = Message(content=message_content, destination=gchat_webhook)
    logger.info(f"m=__main__, message=sending slack message: {message}")
    GChatService.send_message(message)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("load_start_date", help="Start of date range: '%Y-%m-%d'")
    parser.add_argument("load_end_date", help="End of date range: '%Y-%m-%d'")
    parser.add_argument("extraction_type", help="extraction_type - full or incremental")
    parser.add_argument("partitions", help="partition columns")
    parser.add_argument("date_filter_columns", help="partition columns")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    extraction_type = args.extraction_type
    partitions = ast.literal_eval(args.partitions)
    date_filter_columns = ast.literal_eval(args.date_filter_columns)

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, load_start_date={load_start_date}, load_end_date={load_end_date}
                extraction_type={extraction_type}, partitions={partitions}, date_filter_columns={date_filter_columns}
                msg=Starting spark job...
        """
    )

    spark_client = SparkClient()
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    conn_config = _get_conn_config(dbutils, DatabaseEnum.CYBER)

    oracle_consumer = OracleSparkConsumer(conn_config, spark_client)

    oracle_table_name = table_name.upper()
    if extraction_type == "incremental" and date_filter_columns:
        df = oracle_consumer.get_incremental_data_from_table(oracle_table_name, date_filter_columns, load_start_date, load_end_date)
    else:
        df = oracle_consumer.get_data_from_table(oracle_table_name)

    if df.rdd.isEmpty():
        _send_warning(dbutils, environment, table_name)
    else:
        df = df.withColumn("ts_ingestion", current_timestamp())

        if extraction_type == "incremental":
            if date_filter_columns:
                if len(date_filter_columns) > 1:
                    df = df.withColumn("table_partition", (greatest(*[col(c) for c in date_filter_columns])))
                else:
                    df = df.withColumn("table_partition", (col(date_filter_columns[0])))
                partition = "table_partition"
            else:
                partition = "ts_ingestion"

            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column(partition)
                .output()
            )

        db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
        spark_metastore_service = SparkMetastoreService(SparkClient())
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        # create database if it doesn't exists
        database_name = db_info["db_raw_databricks"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        database_location = db_info["db_raw_path"]
        spark_metastore_service.create_database(database_name)

        if extraction_type == "incremental":
            IncrementalTableLoaderPipeline(
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None,
                partitions=partitions,
            ).load_and_register(df, format_options)
        else:
            FullTableLoaderPipeline(
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None
            ).load_and_register(df, format_options)
