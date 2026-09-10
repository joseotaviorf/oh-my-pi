import json
import logging
import os
from argparse import ArgumentParser

from quintoandar_gsheets_api_client.clients import GoogleSheetsClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.api_consumers.gsheets_consumer import GsheetsConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.gsheets_ingestion_alert import format_gsheet_ingestion_alert
from bietlejuice.services.gsheets_service import GsheetsService
from bietlejuice.services.messaging_services.alert_channel_service import (
    AlertChannelService,
)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_gsheets_by_context_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __get_auth(dbutils, credentials_scope, credentials_key):
    """
    This method gets credentials from the Gsheets API.
    @param dbutils: DBUtils.
    @return: dict and str
    """
    credentials = json.loads(
        dbutils.secrets.get(scope=credentials_scope, key=credentials_key)
    )
    scope = credentials.pop("scope")
    return credentials, scope


TIMEOUT_LIMIT = 5 * 60


def __alert_not_ingesting_sheet(sheet_details, exeption, gchat_webhook, dag_name=None):
    message = format_gsheet_ingestion_alert(sheet_details, exeption, dag_name=dag_name)
    message_error = Message(content=message, destination=gchat_webhook)
    return GChatService.send_message(message_error)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name", help="table name to insert into datalake")
    parser.add_argument(
        "sheet_details",
        help="gsheets sheet name, sheet id, and (optional) preload time in seconds",
    )
    parser.add_argument("dag_name", help="DAG name")
    parser.add_argument("credentials_key", help="credentials to access gsheets API")
    parser.add_argument(
        "credentials_scope", help="credentials scope to access gsheets API"
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
    parser.add_argument(
        "--alert-channel",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
        help=(
            "Optional GchatWebhooksEnum keyword from the DAG declaration. "
            "Falls back to AE_ALERTS_PROD / AE_ALERTS_FORNO when omitted."
        ),
    )

    args = parser.parse_args()

    environment = args.environment
    os.environ["ENVIRONMENT"] = environment
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    table_name = args.table_name
    sheet_details = json.loads(args.sheet_details)
    partitions_cols = ["year", "month", "day"]
    dag_name = args.dag_name
    credentials_key = args.credentials_key
    credentials_scope = args.credentials_scope
    alert_channel = args.alert_channel

    logger.info(
        f"""
                m=__main__, environment={environment}, schema={schema}, datalake_bucket={datalake_bucket},
                table_name={table_name}, execution_date=execution_date msg=Starting spark job...
        """
    )

    # Initializing clients
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils, credentials_scope, credentials_key)
    gsheets_client = GoogleSheetsClient(credentials, scope, timeout=TIMEOUT_LIMIT)
    spark_client = SparkClient(app_name=JOB_NAME)
    gsheets_consumer = GsheetsConsumer(gsheets_client, spark_client)

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, schema, datalake_bucket
    )
    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )
    database_name = datalake_info["db_raw_databricks"]
    clean_database_name = datalake_info["db_clean_databricks"]
    spark_metastore_service.create_database(database_name)
    spark_metastore_service.create_database(clean_database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    database_location = datalake_info["db_raw_path"]
    if args.target_database_name and args.target_table_name:
        from bietlejuice.base.validation.target_resolver import (
            validation_database_location,
        )

        write_table_name = args.target_table_name
        database_location = validation_database_location(
            datalake_bucket, database_name
        ).replace("s3a://", "s3://")
        database_name = args.target_database_name
        table_name = write_table_name
        spark_metastore_service.create_database(database_name)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    s3_loader = S3Loader()

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    is_able_to_load = True
    try:
        df = gsheets_consumer.get_sheet_df(
            sheet_details["sheet_name"],
            sheet_details["sheet_id"],
            sheet_details["clean_table_name"],
            sheet_details.get("partitioned"),
            sheet_details.get("preload_time_in_seconds"),
            header_row=sheet_details.get("header_row", 1),
        )
        service = GsheetsService(schema=schema)
        df = service.clean_unsupported_column_names(df)
        # validate data before loading
        service.validate_clean_query_against_raw(
            dag_name,
            spark_client,
            df,
            sheet_details["raw_table_name"],
            sheet_details["clean_table_name"],
        )

        logger.info(
            f"""
                m={JOB_NAME}, table_name={table_name}, msg=sheet is able to be loaded!"
            """
        )

    except Exception as e:
        is_able_to_load = False

        gchat_webhook = AlertChannelService(
            dbutils=dbutils
        ).get_gsheets_failure_webhook_url(
            environment=environment,
            alert_channel=alert_channel,
        )

        message_sent = __alert_not_ingesting_sheet(
            sheet_details, e, gchat_webhook, dag_name=dag_name
        )
        logger.error(
            f"""
                m={JOB_NAME}, table_name={table_name}, msg=Sheet was not loaded, message_sending_result={message_sent},
                alert_channel={alert_channel}, exception={e}"
            """
        )

    if is_able_to_load:
        table_partitions = partitions_cols if sheet_details.get("partitioned") else []

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=table_partitions or None,
        )

        # partitions must be passed through: update_metastore defaults it to [], so a
        # partitioned sheet was previously registered as a flat table over a directory
        # of year=/month=/day= subdirs, with the partition keys declared as ordinary
        # columns that do not exist in the files.
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions=table_partitions,
        )
        if table_partitions:
            spark_metastore_service.create_new_partitions_from_df(
                df=df,
                database_name=database_name,
                table_name=table_name,
                partition_cols=table_partitions,
            )
        logger.info(
            f"""
                m={JOB_NAME}, table_name={table_name}, msg=sheet fully loaded!"
            """
        )
