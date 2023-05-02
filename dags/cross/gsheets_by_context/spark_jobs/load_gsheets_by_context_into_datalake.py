import logging
import json

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from bietlejuice.base.api import APIEnum
from bietlejuice.base.notification import SlackWebhooksEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.consumers.api_consumers.gsheets_consumer import GsheetsConsumer
from bietlejuice.services.gsheets_service import GsheetsService
from bietlejuice.services.slack_service import SlackService

JOB_NAME = "load_gsheets_by_context_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __get_auth(dbutils):
    """
    This method gets credentials from the Gsheets API.
    @param dbutils: DBUtils.
    @return: dict and str
    """
    credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.GSHEETS_CREDENTIALS)
    )
    scope = credentials.pop("scope")
    return credentials, scope


SLACK_MSG_HEADER = ":alert: *Gsheet ingestion failures*\n>The following sheet have errors have not been ingested on this Run."
TIMEOUT_LIMIT = 5 * 60


def __alert_not_ingesting_sheet(sheet_details, exeption, slack_channel):
    msg = """:sheets: Sheet: <{}|{}> (ID: {})\n _Owner team: {}._\n\tError: ```{}```"""
    sheet_url = f"https://docs.google.com/spreadsheets/d/{sheet_details['sheet_id']}"
    error_trace = str(exeption).split("\n")[0]
    # remove chars that break slack messaging and limit error msg to 150 chars
    for bad_char in ["`", '"']:
        error_trace = error_trace.replace(bad_char, "")
    error_trace[slice(0, 150)]
    msg = msg.format(
        sheet_url,
        sheet_details["clean_table_name"],
        sheet_details["sheet_id"],
        sheet_details["sheet_context"],
        error_trace,
    )
    error_list = [(SLACK_MSG_HEADER, slack_channel), (msg, slack_channel)]
    return SlackService.send_slack_errors(error_list)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name", help="table name to insert into datalake")
    parser.add_argument(
        "sheet_details",
        help="gsheets sheet name, sheet id, and (optional) preload time in seconds",
    )

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    sheet_details = json.loads(args.sheet_details)
    partitions_cols = ["year", "month", "day"]

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, execution_date=execution_date msg=Starting spark job...
        """
    )

    # Initializing clients
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils)
    gsheets_client = GoogleSheetsClient(credentials, scope, timeout=TIMEOUT_LIMIT)
    spark_client = SparkClient()
    gsheets_consumer = GsheetsConsumer(gsheets_client, spark_client)

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    database_location = datalake_info["db_raw_path"]
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
        )
        # validate data before loading
        GsheetsService().validate_clean_query_against_raw(
            "gsheets_by_context",
            spark_client,
            df,
            sheet_details.get("sheet_context"),
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
        slack_channel = dbutils.secrets.get(
            scope="quintoandar", key=SlackWebhooksEnum.ALERTS_DE_AIRFLW_DGS
        )
        message_sent = __alert_not_ingesting_sheet(sheet_details, e, slack_channel)
        logger.error(
            f"""
                m={JOB_NAME}, table_name={table_name}, msg=Sheet was not loaded, message_sending_result={message_sent},
                exception={e}"
            """
        )

    if is_able_to_load:
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partitions_cols if sheet_details.get("partitioned") else None,
        )

        spark_metastore_loader.update_metastore(
            df, database_name, table_name, format_options, database_location
        )
        logger.info(
            f"""
                m={JOB_NAME}, table_name={table_name}, msg=sheet fully loaded!"
            """
        )
