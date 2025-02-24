from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger
import datetime as dt

from bietlejuice.base.db import DatalakeMetastoreMapping
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

JOB_NAME = "load_cypress_reports_raw"

def _generate_date_range(load_start_date, load_end_date):
    start_date = dt.datetime.strptime(load_start_date, "%Y-%m-%d")
    end_date = dt.datetime.strptime(load_end_date, "%Y-%m-%d")
    date_index = [start_date + dt.timedelta(days=x) for x in range(0, (end_date - start_date).days + 1)]

    logger.info(
        f"""m=_generate_date_range, msg=Getting data from {start_date} to {end_date}..."""
    )

    return date_index

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    config_service = ConfigurationService(source)
    datalake_metastore_mapper = DatalakeMetastoreMapping(source=source , bucket=datalake_bucket)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    cypress_bucket = config_service.get_config("cypress_bucket")
    schema = config_service.get_config("schema")
    raw_sql = config_service.get_config("raw_sql")

    logger.info(
        f"""m={JOB_NAME}, environment={env}, source={source}, datalake_bucket={datalake_bucket}, 
        msg=Starting spark job..."""
    )

    spark_client = SparkClient()
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    df_service = SparkDataFrameService()

    db_info = datalake_metastore_mapper.get_all_datalake_info()
    database_name = db_info["db_raw_name"]
    database_location = db_info["db_raw_path"]

    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    if env == 'prod':
        key = GchatWebhooksEnum.AE_ALERTS_PROD
    else:
        key = GchatWebhooksEnum.AE_ALERTS_FORNO

    gchat_webhook = dbutils.secrets.get(
        scope="quintoandar", key=key
    )

    spark_metastore_service.create_database(database_name)

    logger.info(f"""m={JOB_NAME}, source_bucket={cypress_bucket}, msg=Getting data from bucket...""")

    for execution_date in _generate_date_range(load_start_date=load_start_date, load_end_date = load_end_date):
        date = execution_date.strftime('%Y-%m-%d')
        logger.info(f"""m={JOB_NAME}, source_bucket={cypress_bucket}, msg=Getting data on date: {date}""")

        df = None
        
        try:
            df = (
                spark_client.conn.read.schema(schema)
                .option("multiLine", True)
                .option("mode", "PERMISSIVE")
                .json(f"s3://{cypress_bucket}/*/{date}/*/*.json")
            )

            if df is not None:
                temp_table_raw = "temp_raw"
                df.createOrReplaceTempView(temp_table_raw)
                df = spark_client.conn.sql(raw_sql.format(table_name=temp_table_raw))

                logger.info(f"""m={JOB_NAME}, source_bucket={cypress_bucket}, table_name={temp_table_raw}, msg=Loading raw data on bucket...""")
                s3_loader.load_df(
                    df=df,
                    format_options=SparkTableStorageFormat.DEFAULT_RAW,
                    s3_path=f"{database_location}{source}",
                    partitions=raw_partition_cols,
                    compression="gzip"
                )
                
                logger.info(f"""m={JOB_NAME}, source_bucket={cypress_bucket}, table_name={source}, msg=Update metastore...""")
                spark_metastore_loader.update_metastore(
                    df=df,
                    database_name=database_name,
                    table_name=source,
                    format_options=SparkTableStorageFormat.DEFAULT_RAW,
                    database_location=database_location,
                    partitions=raw_partition_cols,
                )

                spark_metastore_service.create_new_partitions_from_df(
                    df=df,
                    database_name=database_name,
                    table_name=source,
                    partition_cols=raw_partition_cols,
                ) 

            else:
                logger.info(f"""m={JOB_NAME}, source_bucket={cypress_bucket}, msg=These dataframe is empty...""")

                continue
            
        except Exception as e:
            logger.warning(f"""m={JOB_NAME}, msg={e}.""")

            message_content = (
                f"⚠️\n"
                f"DAG: *{source}*\n"
                f"Owner: @ae-growth\n"
                f"Environment: *{env}*\n"
                f"Status: *FAILED*\n"
                f"Existence validation failed for `{dt.datetime.now().strftime('%Y-%m-%d')}`\n"
                f"Error:'{e}'\n"
            )

            message = Message(content=message_content, destination=gchat_webhook)

            if execution_date.weekday() < 5:
                GChatService.send_message(message)

            continue