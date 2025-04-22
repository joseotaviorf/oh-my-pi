import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from typing import List, Union

from quintoandar_logger import QuintoAndarLogger

from pyspark.sql import functions, DataFrame
from pyspark.sql.types import StructField, StructType, StringType

from quintoandar_gsheets_api_client.producer import GoogleSheetsWriter
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from bietlejuice.base.api import APIEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.api_consumers.gsheets_consumer import GsheetsConsumer


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_scan_results_into_gsheet"
TIMEOUT_LIMIT = 5 * 60

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

@logger(exclude_return=True)
def write_data_on_sheet(
    client: GoogleSheetsWriter,
    sheet_name: str,
    sheet_id: str,
    data: Union[List[List]],
    header: Union[List, None] = None,
):
    """
    :param sheet_name: Sheet name for data
    :param sheet_id: Sheet ID for data
    :param data: DataFrame with the data to be written on gsheets.
    """

    if header:
        data.insert(0, header)

    client.write(
        sheet_name=sheet_name,
        sheet_id=sheet_id,
        data=data
    )


def _get_payloads_from_datalake(spark_client:SparkClient, execution_date:str) -> list:
    """
    This function gets the data from the reverse tables and transforms it into a list of payloads

    :param spark_client: SparkClient to connect to local spark
    :param execution_date: execution date to be used to filter the data. Format is YYYY-MM-DD

    :return: list of lists
    """
    execution_date_dt = datetime.strptime(execution_date, "%Y-%m-%d")
    year = execution_date_dt.year
    month = execution_date_dt.month
    day = execution_date_dt.day

    logger.info(f"m=_get_payloads_from_datalake, message=Fetching data from datalake, year={year}, month={month}, day={day}")

    query = f"""
    SELECT
        id_entity,
        line_owner,
        email AS email_owner,
        sample,
        sample_summary,
        col_summary,
        initial_eval
    FROM
        reverse_anonymization.scan_entities_found
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    """

    df = spark_client.get_records(query)
    rows = df.rdd.map(lambda row: [str(x) for x in row]).collect()

    logger.info(f"m=_get_payloads_from_datalake, message=Fetched {len(rows)} rows from datalake")
    return rows

def __get_auth(dbutils, credentials_scope, credentials_key):
    """
    This method gets credentials from the Gsheets API.
    @param dbutils: DBUtils.
    @return: dict and str
    """
    credentials = json.loads(
        dbutils.secrets.get(scope=credentials_scope, key=credentials_key)
    )

    credentials.pop("scope")
    scope = "https://www.googleapis.com/auth/spreadsheets"

    return credentials, scope


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("sheet_name")
    parser.add_argument("sheet_id")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    sheet_name = args.sheet_name
    sheet_id = args.sheet_id
    execution_date = args.execution_date

    logger.info(f"m=main, message=Starting job. sheet_name={sheet_name}, sheet_id={sheet_id}, execution_date= {execution_date}")

    header = [
        "id_entity",
        "line",
        "owner_email",
        "sample_results_json",
        "sample_summary",
        "col_summary",
        "initial_eval",
        "final_check",
        "is_pii"
    ]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils, "quintoandar", APIEnum.GSHEETS_CREDENTIALS)
    gsheets_client = GoogleSheetsClient(credentials, scope, timeout=TIMEOUT_LIMIT)
    spark_client = SparkClient()

    gsheets_producer = GoogleSheetsWriter(gsheets_client)

    new_data_scan = _get_payloads_from_datalake(spark_client, execution_date)

    gsheets_consumer = GsheetsConsumer(gsheets_client, spark_client)

    logger.info(f"m=main, message=Fetching data from gsheets. sheet_name={sheet_name}, sheet_id={sheet_id}")
    gsheet_current_data = gsheets_consumer.get_sheet_df(sheet_name, sheet_id, "pii_scan_results_validation")
    logger.info(f"m=main, message=Found {len(gsheet_current_data.collect())} rows on gsheets.")

    gsheet_current_data_list = gsheet_current_data.filter("final_check != ''").rdd.map(lambda row: [str(x) for x in row]).collect()

    logger.info(f"m=main, message= {len(gsheet_current_data_list)} still need validation from owners. Keeping on gsheets.")
    logger.info(f"m=main, message= {len(new_data_scan)} new data to be written on gsheets.")

    payload = new_data_scan + gsheet_current_data_list
    payload.insert(0, header)

    gsheets_producer.write(sheet_name, sheet_id, payload)

if __name__ == "__main__":
    main()
