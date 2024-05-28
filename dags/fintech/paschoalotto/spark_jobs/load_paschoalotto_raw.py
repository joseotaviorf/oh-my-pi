import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from ast import literal_eval
import boto3

from pyspark.sql.functions import current_timestamp, lit
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.pipeline import LayerEnum

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (SparkDataFrameService,
                                    SparkTableStorageFormat)
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import (FullTableLoaderPipeline,
                                  IncrementalTableLoaderPipeline)

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

from pyspark.sql import DataFrame
from pyspark.sql.functions import (expr, when)
from functools import reduce

JOB_NAME = "load_paschoalotto_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def __build_warning_messages(environment, s3_path_prefix, table_list, date):

    messages = []
    for table_name in table_list:
        messages.append(
            f"⚠️\n"
            f"Environment: *{environment}*\n"
            f"Table: `{s3_path_prefix}/{table_name}`\n"
            f"Status: *FAILED*\n"
            f"*Existence validation failed for `{date}`\n"
        )

    return messages

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source")
    parser.add_argument("date_to_ingest", help="Date to be used in filtering the files. Format: '%Y-%m-%d'",)
    parser.add_argument("table_name", help="translated table name (based on original_table_name)")
    parser.add_argument("load_incremental", help="indicates wheter the load is incremental or not (full)")
    parser.add_argument("partition_cols", help="table partition")
    parser.add_argument("format", help="S3 object format")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_root_path = args.source_root_path
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    load_incremental = literal_eval(args.load_incremental)
    partition_cols = json.loads(args.partition_cols)
    format = json.loads(args.format)

    logger.info(
        f"""m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        source_root_path={source_root_path}, partition_cols= {partition_cols}, date_to_ingest={date_to_ingest},
        table_name={table_name}, load_incremental = {load_incremental}.
        msg=Starting spark job...
        """)

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

    s3_client = boto3.resource('s3')
    my_bucket = s3_client.Bucket(source_root_path)


    tables_to_send_warning = []
    filtered_files = []
    prefix = f'{table_name}'
    files_list = [object_summary.key for object_summary in my_bucket.objects.filter(Prefix=prefix)]


    for file in files_list:
      if 'quintocred' not in file:
        dt_pattern = f"{table_name}_{date_to_ingest}.{format}"
        if file == dt_pattern:
          filtered_files.append(file)
      else:
        dt_pattern = f"{table_name}_quintocred_{date_to_ingest}.{format}"
        if file == dt_pattern:
          filtered_files.append(file)

    dfs = []
    if len(filtered_files) > 0:

        for path in filtered_files:
            df = spark.read.parquet(f"s3://{source_root_path}/{path}")
            df = df.withColumn("s3_file_name", lit(path))
            df = df.withColumn("context", when(expr("s3_file_name NOT LIKE '%quintocred%'"), lit('quintoandar')).otherwise(lit('quintocred')))
            df = df.withColumn("ts_load", current_timestamp())
            datetime_file = datetime.strptime(date_to_ingest, "%Y-%m-%d")

            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(datetime_file)
                .output()
            )
            dfs.append(df)

        df = reduce(DataFrame.unionAll, dfs)

        if load_incremental:
            IncrementalTableLoaderPipeline(
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None,
                partitions=partition_cols,
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
            "m=__main__, msg= No files were found on S3 bucket. Ending process without loading anything."
        )
        tables_to_send_warning.append(table_name)

    if tables_to_send_warning:
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
            tables_to_send_warning,
            date_to_ingest,
        )

        for message_content in messages:
            message = Message(content=message_content, destination=gchat_webhook)
            logger.info(f"m=__main__, message=sending slack message: {message}")
            GChatService.send_message(message)
