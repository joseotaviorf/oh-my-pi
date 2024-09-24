import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from pyspark.sql.functions import current_timestamp, lit
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.pipeline import LayerEnum

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (SparkDataFrameService,
                                    SparkTableStorageFormat)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import FullTableLoaderPipeline, IncrementalTableLoaderPipeline
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum


JOB_NAME = "load_webhelp_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_azure_credentials():
    DATABRICKS_SCOPE = "quintoandar"
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key="AZURE_WEBHELP"
    )
    credentials = json.loads(json_credentials)

    return credentials['storage_account_name'], credentials['storage_account_access_key']

def _generate_date_range(load_start_date, load_end_date):
    start_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    end_date = datetime.strptime(load_end_date, "%Y-%m-%d")
    date_index = [start_date + timedelta(days=x) for x in range(0, (end_date - start_date).days + 1)]
    return date_index

def __build_warning_messages(environment, s3_path_prefix, table_name, dates):

    messages = []
    for date in dates:
        messages.append(
            f"⚠️\n"
            f"DAG: webhelp\n"
            f"Environment: *{environment}*\n"
            f"Table: `{s3_path_prefix}/{table_name}`\n"
            f"Status: *FAILED*\n"
            f"Existence validation failed for `{date}`\n"
        )

    return messages

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("azure_container_name", help="azure container name")
    parser.add_argument("azure_sub_folder", help="azure sub folder")
    parser.add_argument("format", help="object format")
    parser.add_argument("table_name", help="table name")
    parser.add_argument("load_start_date", help="Start of date range: '%Y-%m-%d'")
    parser.add_argument("load_end_date", help="End of date range: '%Y-%m-%d'")
    parser.add_argument("extraction_type", help="extraction_type - full or incremental")
    parser.add_argument("partitions", help="partition columns")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    azure_container_name = args.azure_container_name
    azure_sub_folder = args.azure_sub_folder
    format = args.format
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    extraction_type = args.extraction_type
    partitions = json.loads(args.partitions)


    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    container_name = "lake-quinto-andar-sftp"
    azure_account_name, azure_account_key = get_azure_credentials()
    spark.conf.set("fs.azure.account.key." + azure_account_name + ".blob.core.windows.net", azure_account_key)


    base_blob_storage_path = f"wasbs://{azure_container_name}@{azure_account_name}.blob.core.windows.net/EXPORTACOES/{azure_sub_folder}"

    azure_table_name = table_name.upper()

    dates_to_ingest = _generate_date_range(load_start_date, load_end_date) if extraction_type == "incremental" else _generate_date_range(load_end_date, load_end_date)

    logger.info(f"Dates do process: load_start_date={load_start_date}, load_end_date = {load_end_date}")


    days_to_send_warning = []
    for date_to_ingest in dates_to_ingest:
        date_to_ingest_formatted = date_to_ingest.strftime("%Y-%m-%d")

        logger.info(
        f"""m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        azure_container_name={azure_container_name}, azure_sub_folder = {azure_sub_folder}, format = {format},
        table_name={table_name}, date_to_ingest = {date_to_ingest_formatted},
        extraction_type = {extraction_type}, partitions = {partitions}.
        msg=Starting spark job...
        """)


        if partitions:
            blob_storage_path = f"{base_blob_storage_path}/{azure_table_name}/{date_to_ingest.year}/{date_to_ingest.month}/{date_to_ingest.day}/"
        else:
            blob_storage_path = f"{base_blob_storage_path}/{azure_table_name}/"

        logger.info(
            f"""m=__main__, msg=File name to be processed: {blob_storage_path}"""
        )

        try:
            df = s3_consumer.get_data_from_file(path=blob_storage_path, format=format)
            logger.info(f"Original dataframe - Displaying a sample of 2 rows out of a total of {df.count()} rows")
            df.show(2)
        except AnalysisException as error:
            logger.warning(
                f"""
                m=__main__, msg=No data found for {blob_storage_path}.

                Exception: {error}
                """
            )
            days_to_send_warning.append(date_to_ingest_formatted)
            continue

        df = df.withColumn("subfolder", lit(azure_sub_folder))

        # Rename columns to lowercase
        columns = df.columns
        for col in columns:
            df = df.withColumnRenamed(col, col.lower())

        # Add ts_load columns
        df = df.withColumn("ts_load", current_timestamp())

        if partitions:
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(date_to_ingest)
                .output()
            )
        logger.info(f"Final dataframe - Displaying a sample of 5 rows out of a total of {df.count()} rows")
        df.show(5)
        logger.info(f"""Starting loading data into datalake database_name = {database_name}, table_name = {table_name}, extraction_type == {extraction_type}""")
        if not df.isEmpty():
            if extraction_type == "incremental":
                IncrementalTableLoaderPipeline(
                    database_name=database_name,
                    table_name=table_name,
                    database_location=database_location,
                    layer=LayerEnum.RAW,
                    query=None,
                    partitions=partitions,
                ).load_and_register(df, format_options)
            elif extraction_type == "full":
                FullTableLoaderPipeline(
                    database_name=database_name,
                    table_name=table_name,
                    database_location=database_location,
                    layer=LayerEnum.RAW,
                    query=None
                ).load_and_register(df, format_options)
            else:
                raise "Pass as param a valid extraction_type type"
        else:
                logger.warning(
                f"m=__main__, msg= File {blob_storage_path}, table_name={azure_table_name} is empty. Ending process without loading anything."
                )
                days_to_send_warning.append(date_to_ingest_formatted)

    if days_to_send_warning:
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        if environment == 'prod':
            key = GchatWebhooksEnum.FINTECH_ALERTS_PROD
        else:
            key = GchatWebhooksEnum.AE_ALERTS_FORNO

        gchat_webhook = dbutils.secrets.get(
            scope="quintoandar", key=key
        )

        messages = __build_warning_messages(
            environment,
            blob_storage_path,
            azure_table_name,
            days_to_send_warning,
        )

        for message_content in messages:
            message = Message(content=message_content, destination=gchat_webhook)
            logger.info(f"m=__main__, message=sending slack message: {message}")
            GChatService.send_message(message)
