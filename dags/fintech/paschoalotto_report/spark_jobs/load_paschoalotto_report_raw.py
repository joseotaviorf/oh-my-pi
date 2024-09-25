import json
import logging
from argparse import ArgumentParser
from datetime import (datetime, timedelta)
from functools import reduce

import boto3
from pyspark.sql import DataFrame
from pyspark.sql.functions import (current_timestamp, expr, lit, when)

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (BaseDBUtils, SparkDataFrameService, SparkTableStorageFormat)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.pipeline import (FullTableLoaderPipeline, IncrementalTableLoaderPipeline)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger



JOB_NAME = "load_paschoalotto_report_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def __build_warning_messages(environment, s3_path_prefix, table_name, dates):

    messages = []
    for date in dates:
        messages.append(
            f"⚠️\n"
            f"DAG: paschoalotto_report\n"
            f"Environment: *{environment}*\n"
            f"Table: `{s3_path_prefix}/{table_name}`\n"
            f"Status: *FAILED*\n"
            f"Existence validation failed for `{date}`\n"
        )

    return messages

def _generate_date_range(load_start_date, load_end_date):
    start_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    end_date = datetime.strptime(load_end_date, "%Y-%m-%d")
    date_index = [start_date + timedelta(days=x) for x in range(0, (end_date - start_date).days + 1)]
    return date_index


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source")
    parser.add_argument("format", help="S3 object format")
    parser.add_argument("table_name", help="translated table name (based on original_table_name)")
    parser.add_argument("load_start_date", help="Start of date range: '%Y-%m-%d'")
    parser.add_argument("load_end_date", help="End of date range: '%Y-%m-%d'")
    parser.add_argument("extraction_type", help="indicates wheter the load is incremental or not (full)")
    parser.add_argument("partitions", help="table partition")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_root_path = args.source_root_path
    format = args.format
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    extraction_type = args.extraction_type
    partitions = json.loads(args.partitions)

    logger.info(
        f"""m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        source_root_path={source_root_path}, partitions= {partitions}, load_start_date={load_start_date},
        load_end_date = {load_end_date}, table_name={table_name}, extraction_type = {extraction_type}.
        msg=Starting spark job...
        """)

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_client = boto3.resource('s3')
    my_bucket = s3_client.Bucket(source_root_path)


    days_to_send_warning = []

    prefix = f'{table_name}'
    files_list = [object_summary.key for object_summary in my_bucket.objects.filter(Prefix=prefix)]

    dates_to_ingest = _generate_date_range(load_start_date, load_end_date)
    for date_to_ingest in dates_to_ingest:
        date_to_ingest_formatted = date_to_ingest.strftime("%Y-%m-%d")
        filtered_files = []
        for file in files_list:
            if 'quintocred' in file:
                file_name = f"{table_name}_quintocred"
            elif 'tb_arquivo' in file:
                file_name = f"{table_name}_quintoandar"
            else:
                file_name = table_name
            dt_pattern = f"{file_name}_{date_to_ingest_formatted}.{format}"

            if file == dt_pattern:
                filtered_files.append(file)
        dfs = []
        if len(filtered_files) > 0:
            for path in filtered_files:
                df = s3_consumer.get_data_from_file(path=f"s3://{source_root_path}/{path}", format=format)
                df = df.withColumn("s3_file_name", lit(path))
                df = df.withColumn("context", when(expr("s3_file_name NOT LIKE '%quintocred%'"), lit('quintoandar')).otherwise(lit('quintocred')))
                df = df.withColumn("ts_load", current_timestamp())
                datetime_file = datetime.strptime(date_to_ingest_formatted, "%Y-%m-%d")

                df = (
                    SparkDataFrameService()
                    .input(df)
                    .create_year_month_day_columns_from_date(datetime_file)
                    .output()
                )
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)

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
                else:
                    FullTableLoaderPipeline(
                        database_name=database_name,
                        table_name=table_name,
                        database_location=database_location,
                        layer=LayerEnum.RAW,
                        query=None
                    ).load_and_register(df, format_options)
            else:
                logger.warning(
                f"m=__main__, msg= File {dt_pattern} is empty. Ending process without loading anything."
                )
                days_to_send_warning.append(date_to_ingest_formatted)
        else:
            logger.warning(
                "m=__main__, msg= No files were found on S3 bucket. Ending process without loading anything."
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
            f"s3://{source_root_path}",
            table_name,
            days_to_send_warning,
        )

        for message_content in messages:
            message = Message(content=message_content, destination=gchat_webhook)
            logger.info(f"m=__main__, message=sending slack message: {message}")
            GChatService.send_message(message)
