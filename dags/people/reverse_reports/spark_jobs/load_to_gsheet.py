"""
Spark job that exports reverse_reports DAG tables to Google Sheets.

Reads from reverse_reports.{table_name} and writes to the specified Google Sheet.
Each table can target a different sheet (sheet_id) and tab (sheet_tab).

Uses SELECT * to keep the job generic so any table shape works automatically.
Column names are derived from the DataFrame schema after excluding partition cols.
"""

import json
import logging
import time
from argparse import ArgumentParser
from datetime import date, datetime
from decimal import Decimal
from math import isnan, isinf

import gspread
from google.oauth2.service_account import Credentials as ServiceAccountCredentials
from gspread.exceptions import WorksheetNotFound

from quintoandar_gsheets_api_client.clients import GoogleSheetsClient
from quintoandar_gsheets_api_client.producer import GoogleSheetsWriter

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient


CREDENTIALS_SCOPE = "people"
FORNO_SHEET_ID = "10p4xUfeoTKxJB3RtrO8-Jf8O7sdnll8fT_PXZPB-EgU"
JOB_NAME = "load_to_gsheet"
TIMEOUT_LIMIT = 5 * 60
SCHEMA = "reverse_reports"

logger = logging.getLogger(JOB_NAME)

WRITE_RETRY_DELAYS_SECONDS = [60, 60, 60, 60, 60, 120, 180]
GSHEETS_SERVICE_ACCOUNT_EMAIL = "gsheets-people-access@airflow-186119.iam.gserviceaccount.com"


def _is_retriable_gsheets_error(e: Exception) -> bool:
    """
    Return True if the exception is a retriable Google Sheets API error.

    Retriable: 429 rate limit, 503 unavailable, resource exhausted, deadline exceeded.
    """
    error_msg = str(e).upper()
    if "429" in error_msg or "RESOURCE_EXHAUSTED" in error_msg or "RATE_LIMIT_EXCEEDED" in error_msg:
        return True
    if "503" in error_msg or "UNAVAILABLE" in error_msg or "DEADLINE_EXCEEDED" in error_msg:
        return True
    if hasattr(e, "code") and e.code in (429, 503):
        return True
    if hasattr(e, "resp") and getattr(e.resp, "status", None) in (429, 503):
        return True
    return False


def _is_not_found_gsheets_error(e: Exception) -> bool:
    """Return True if the exception is a 404 NOT_FOUND (spreadsheet or sheet does not exist)."""
    error_msg = str(e).upper()
    if "404" in error_msg or "NOT_FOUND" in error_msg:
        return True
    if hasattr(e, "code") and e.code == 404:
        return True
    if hasattr(e, "resp") and getattr(e.resp, "status", None) == 404:
        return True
    return False


def _is_missing_sheet_tab_error(e: Exception, sheet_tab: str) -> bool:
    """Return True if the error indicates a missing or invalid sheet tab."""
    error_msg = str(e)
    if sheet_tab not in error_msg:
        return False
    tab_error_indicators = [
        "Unable to parse range",
        "not found",
        "does not exist",
        "Invalid range",
        "No sheet",
    ]
    return any(ind in error_msg for ind in tab_error_indicators)


def _cell_value_to_str(value) -> str:
    """
    Convert a Spark cell value to a GSheets-safe string.

    Handles: None, Decimal, date/datetime, bool, NaN/inf, and formula injection
    (values starting with = or + are prefixed with a quote).
    Datetime with time component uses %Y-%m-%d %H:%M:%S; date-only uses %Y-%m-%d.
    """
    if value is None:
        return ""
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, date) and not isinstance(value, datetime):
        return value.strftime("%Y-%m-%d")
    if isinstance(value, datetime):
        if value.hour == 0 and value.minute == 0 and value.second == 0:
            return value.strftime("%Y-%m-%d")
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, bool):
        return "Yes" if value else "No"
    if isinstance(value, float) and (isnan(value) or isinf(value)):
        return ""
    s = str(value)
    if s and s[0] in ("=", "+"):
        return "'" + s
    return s


def _write_with_retries(writer, sheet_tab: str, sheet_id: str, payload: list) -> None:
    """
    Write payload to GSheets with retry and progressive backoff on retriable errors.

    Only retries on 429/503; fails immediately on 404, PERMISSION_DENIED, etc.
    Uses progressive backoff: [60, 60, 60, 60, 60, 120, 180] seconds.
    """
    delays = WRITE_RETRY_DELAYS_SECONDS
    for attempt, delay in enumerate(delays + [None]):
        try:
            writer.write(sheet_tab, sheet_id, payload)
            return
        except Exception as e:
            error_msg = str(e)
            logger.warning("GSheets write failed (attempt %d): %s", attempt + 1, e)

            if _is_retriable_gsheets_error(e):
                if delay is not None:
                    logger.warning(
                        "Rate limit or temporary error. Waiting %ds before next try...",
                        delay,
                    )
                    time.sleep(delay)
                else:
                    raise RuntimeError(
                        f"Quota/rate limit exceeded. All retries failed. Last error: {e}"
                    ) from e
                continue

            if _is_not_found_gsheets_error(e):
                raise RuntimeError(
                    "Spreadsheet or sheet not found. Check sheet link and tab name."
                ) from e

            if _is_missing_sheet_tab_error(e, sheet_tab):
                raise RuntimeError(
                    f"Sheet tab '{sheet_tab}' not found or invalid. Check tab name."
                ) from e

            if "PERMISSION_DENIED" in error_msg.upper():
                raise RuntimeError(
                    f"Bot does not have access to the gsheet. Share it with: {GSHEETS_SERVICE_ACCOUNT_EMAIL}"
                ) from e

            if delay is not None:
                logger.warning("Waiting %ds before next try...", delay)
                time.sleep(delay)
            else:
                raise RuntimeError(f"All retries failed. Last error: {e}") from e


def _get_auth(dbutils, credentials_scope: str, credentials_key: str):
    """
    Retrieve Google Sheets API credentials from Databricks secrets.

    :param dbutils: DBUtils instance.
    :param credentials_scope: Databricks secret scope name.
    :param credentials_key: Secret key for the credentials JSON.
    :return: Tuple of (credentials dict, scope string).
    """
    credentials = json.loads(
        dbutils.secrets.get(scope=credentials_scope, key=credentials_key)
    )
    credentials.pop("scope", None)
    scope = "https://www.googleapis.com/auth/spreadsheets"
    return credentials, scope


def _get_payloads_from_table(
    spark_client: SparkClient, table_name: str, execution_date: str
) -> tuple:
    """
    Fetch data from the reverse table and convert to list of rows for GSheets.

    Uses SELECT * to keep the job generic; columns are derived from the schema.
    Partition columns (year, month, day) are excluded from the output.

    :param spark_client: SparkClient to execute queries.
    :param table_name: Name of the reverse table.
    :param execution_date: Execution date in YYYY-MM-DD format for partition filter.
    :return: Tuple of (header list, rows list).
    """
    execution_dt = datetime.strptime(execution_date, "%Y-%m-%d")
    year = execution_dt.year
    month = execution_dt.month
    day = execution_dt.day

    logger.info(
        "Fetching data from %s.%s (partition: %d-%02d-%02d)",
        SCHEMA,
        table_name,
        year,
        month,
        day,
    )

    query = f"""
        SELECT *
        FROM {SCHEMA}.{table_name}
        WHERE year = {year}
          AND month = {month}
          AND day = {day}
    """

    df = spark_client.get_records(query)
    columns = df.columns
    exclude_cols = {"year", "month", "day"}
    output_columns = [c for c in columns if c not in exclude_cols]

    logger.info("Exporting columns: %s", output_columns)

    rows = (
        df.select(output_columns)
        .rdd.map(lambda row: [_cell_value_to_str(x) for x in row])
        .collect()
    )

    logger.info("Fetched %d rows from %s.%s", len(rows), SCHEMA, table_name)
    return output_columns, rows


def _ensure_worksheet_exists(
    credentials: dict, scope: str, sheet_id: str, sheet_tab: str
) -> None:
    """
    Create the worksheet if it does not exist in the spreadsheet.

    :param credentials: Service account credentials dict.
    :param scope: OAuth scope for Google Sheets API.
    :param sheet_id: Google Sheet ID.
    :param sheet_tab: Worksheet tab name.
    """
    creds = ServiceAccountCredentials.from_service_account_info(
        credentials, scopes=[scope]
    )
    gc = gspread.authorize(creds)
    spreadsheet = gc.open_by_key(sheet_id)
    try:
        spreadsheet.worksheet(sheet_tab)
    except WorksheetNotFound:
        spreadsheet.add_worksheet(title=sheet_tab, rows=1000, cols=26)
        logger.info("Created worksheet %s in sheet %s", sheet_tab, sheet_id)


def main():
    """Export reverse table data to Google Sheet."""
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("table_name", help="Reverse table name")
    parser.add_argument("execution_date", help="Execution date YYYY-MM-DD")
    parser.add_argument("environment", help="Execution environment (forno, prod)")
    parser.add_argument("sheet_id", help="Google Sheet ID")
    parser.add_argument("sheet_tab", help="Google Sheet tab name")

    args = parser.parse_args()
    table_name = args.table_name
    execution_date = args.execution_date
    environment = args.environment
    sheet_id = FORNO_SHEET_ID if environment == "forno" else args.sheet_id
    sheet_tab = args.sheet_tab

    logger.info(
        "Starting export: table=%s, sheet=%s, tab=%s, execution_date=%s",
        table_name,
        sheet_id,
        sheet_tab,
        execution_date,
    )

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    if dbutils is None:
        raise RuntimeError("DBUtils not available. This job must run on Databricks.")

    credentials, scope = _get_auth(
        dbutils, CREDENTIALS_SCOPE, APIEnum.GSHEETS_CREDENTIALS_PEOPLE
    )
    _ensure_worksheet_exists(credentials, scope, sheet_id, sheet_tab)

    gsheets_client = GoogleSheetsClient(credentials, scope, timeout=TIMEOUT_LIMIT)
    gsheets_producer = GoogleSheetsWriter(gsheets_client)
    spark_client = SparkClient()

    header, rows = _get_payloads_from_table(spark_client, table_name, execution_date)
    payload = [header] + rows

    _write_with_retries(gsheets_producer, sheet_tab, sheet_id, payload)

    logger.info(
        "Export completed: table=%s, sheet=%s, tab=%s, rows=%d",
        table_name,
        sheet_id,
        sheet_tab,
        len(rows),
    )


if __name__ == "__main__":
    main()
