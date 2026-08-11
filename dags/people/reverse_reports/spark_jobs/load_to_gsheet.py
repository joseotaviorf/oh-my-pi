"""
Spark job that exports reverse_reports DAG tables to Google Sheets.

Reads from reverse_reports.{table_name} and writes to the specified Google Sheet.
Each table can target a different sheet (sheet_id) and tab (sheet_tab).
"""

import json
import logging
import time
from argparse import ArgumentParser
from datetime import datetime

import numpy as np
import pandas as pd
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient
from quintoandar_gsheets_api_client.producer import GoogleSheetsWriter

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient

CREDENTIALS_SCOPE = "people"
FORNO_SHEET_ID = "10p4xUfeoTKxJB3RtrO8-Jf8O7sdnll8fT_PXZPB-EgU"
JOB_NAME = "load_to_gsheet"
SCHEMA = "reverse_reports"

logger = logging.getLogger(JOB_NAME)

# Aligned with the Databricks sandbox_toolkit export notebook.
GSHEETS_WRITE_CHUNK_SIZE = 10_000
GSHEETS_CHUNK_PAUSE_SECONDS = 2
GSHEETS_SERVICE_ACCOUNT_EMAIL = (
    "gsheets-people-access@airflow-186119.iam.gserviceaccount.com"
)


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


def _is_workbook_cell_limit_error(e: Exception) -> bool:
    """Return True when the workbook hit Google Sheets' 10M cell limit."""
    error_msg = str(e).upper()
    return (
        "10000000" in error_msg
        or "10,000,000" in error_msg
        or "CELLS IN THE WORKBOOK" in error_msg
    )


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


def _raise_for_gsheets_error(e: Exception, sheet_tab: str) -> None:
    """Translate known GSheets API failures into actionable RuntimeError messages."""
    error_msg = str(e)

    if _is_workbook_cell_limit_error(e):
        raise RuntimeError(
            "Google Sheets workbook cell limit exceeded (10M cells). "
            "Remove unused tabs, archive old data, or export to a dedicated spreadsheet."
        ) from e

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


def _run_gsheets_operation(sheet_tab: str, operation, operation_label: str) -> None:
    """Run a single GSheets API call. Retries are handled by the Airflow EMR task."""
    try:
        operation()
    except Exception as e:
        logger.error("GSheets %s failed: %s", operation_label, e)
        _raise_for_gsheets_error(e, sheet_tab)
        raise


def _spark_dataframe_to_gsheets_rows(df, force_int_to_str: bool = False) -> list:
    """
    Format a Spark DataFrame for the Sheets API.

    Returns a list of rows with the header as the first row.
    """
    pdf = df.toPandas()
    for col in pdf.columns:
        if pd.api.types.is_datetime64_any_dtype(pdf[col]):
            if all(pdf[col].dt.time == pd.to_datetime("00:00:00").time()):
                pdf[col] = pdf[col].dt.strftime("%Y-%m-%d")
            else:
                pdf[col] = pdf[col].dt.strftime("%Y-%m-%d %H:%M:%S")
        if pdf[col].dtype == "object":
            pdf[col] = pdf[col].astype(str)
            if any(x.startswith(("=", "+")) for x in pdf[col]):
                pdf[col] = (
                    pdf[col]
                    .astype(str)
                    .apply(lambda x: f"'{x}" if x.startswith(("=", "+")) else x)
                )
        if force_int_to_str and not pd.api.types.is_float_dtype(pdf[col]):
            pdf[col] = pdf[col].apply(lambda x: "'" + str(x) if str(x).isdigit() else x)
    pdf = pdf.replace(
        [np.inf, -np.inf, np.nan, pd.NaT, None, "None", "nan", "'None", "'nan"],
        "",
    )
    rows = pdf.values.tolist()
    rows.insert(0, pdf.columns.tolist())
    return rows


def _iter_payload_write_chunks(payload: list, chunk_size: int) -> list[list]:
    """Split payload into write batches. First batch includes the header row."""
    if not payload:
        return []

    header = payload[0]
    data_rows = payload[1:]
    if not data_rows:
        return [[header]]

    chunks = []
    for start in range(0, len(data_rows), chunk_size):
        batch = data_rows[start : start + chunk_size]
        if start == 0:
            chunks.append([header] + batch)
        else:
            chunks.append(batch)
    return chunks


def _get_worksheet(writer: GoogleSheetsWriter, sheet_id: str, sheet_tab: str):
    """Return the gspread worksheet handle for one tab."""
    return writer.google_sheets_client.gsheets.open_by_key(sheet_id).worksheet(
        sheet_tab
    )


def _write_payload_in_chunks(
    writer: GoogleSheetsWriter,
    sheet_tab: str,
    sheet_id: str,
    payload: list,
    chunk_size: int = GSHEETS_WRITE_CHUNK_SIZE,
) -> None:
    """
    Replace worksheet content, chunking large payloads to avoid Sheets API 500s.

    Small payloads use ``GoogleSheetsWriter.write`` (clear + single update).
    Large payloads write the first chunk with ``writer.write`` (clear + update),
    then ``append_rows`` for the remaining batches — same pattern as the Databricks
    sandbox_toolkit export notebook.
    """
    data_row_count = max(len(payload) - 1, 0)
    if data_row_count <= chunk_size:
        _run_gsheets_operation(
            sheet_tab,
            lambda: writer.write(sheet_tab, sheet_id, payload),
            "write",
        )
        return

    chunks = _iter_payload_write_chunks(payload, chunk_size)
    logger.info(
        "Writing %d rows in %d chunks (chunk_size=%d)",
        data_row_count,
        len(chunks),
        chunk_size,
    )

    _run_gsheets_operation(
        sheet_tab,
        lambda: writer.write(sheet_tab, sheet_id, chunks[0]),
        f"write chunk 1/{len(chunks)}",
    )

    if len(chunks) == 1:
        return

    worksheet = _get_worksheet(writer, sheet_id, sheet_tab)
    for chunk_index, chunk in enumerate(chunks[1:], start=2):
        chunk_label = f"append chunk {chunk_index}/{len(chunks)}"

        def append_chunk(rows=chunk, label=chunk_label):
            worksheet.append_rows(rows, value_input_option="USER_ENTERED")

        _run_gsheets_operation(sheet_tab, append_chunk, chunk_label)

        if chunk_index < len(chunks):
            time.sleep(GSHEETS_CHUNK_PAUSE_SECONDS)


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


def _get_gsheets_writer(dbutils) -> GoogleSheetsWriter:
    """Return a GoogleSheetsWriter configured with People credentials."""
    credentials, scope = _get_auth(
        dbutils, CREDENTIALS_SCOPE, APIEnum.GSHEETS_CREDENTIALS_PEOPLE
    )
    gsheets_client = GoogleSheetsClient(credentials, scope)
    return GoogleSheetsWriter(gsheets_client)


def _get_payloads_from_table(
    spark_client: SparkClient,
    table_name: str,
    execution_date: str,
    database_name: str = SCHEMA,
) -> list:
    """
    Fetch data from the reverse table and convert to GSheets rows (header included).

    Partition columns (year, month, day) are excluded from the export payload.

    :param spark_client: SparkClient to execute queries.
    :param table_name: Name of the reverse table.
    :param execution_date: Execution date in YYYY-MM-DD format for partition filter.
    :return: List of rows with column names as the first row.
    """
    execution_dt = datetime.strptime(execution_date, "%Y-%m-%d")
    year = execution_dt.year
    month = execution_dt.month
    day = execution_dt.day

    logger.info(
        "Fetching data from %s.%s (partition: %d-%02d-%02d)",
        database_name,
        table_name,
        year,
        month,
        day,
    )

    query = f"""
        SELECT *
        FROM {database_name}.{table_name}
        WHERE year = {year}
          AND month = {month}
          AND day = {day}
    """

    df = spark_client.get_records(query)
    exclude_cols = {"year", "month", "day"}
    output_columns = [c for c in df.columns if c not in exclude_cols]

    logger.info("Exporting columns: %s", output_columns)

    payload = _spark_dataframe_to_gsheets_rows(df.select(output_columns))
    row_count = len(payload) - 1
    logger.info("Fetched %d rows from %s.%s", row_count, database_name, table_name)
    return payload


def main():
    """Export reverse table data to Google Sheet."""
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("table_name", help="Reverse table name")
    parser.add_argument("execution_date", help="Execution date YYYY-MM-DD")
    parser.add_argument("environment", help="Execution environment (forno, prod)")
    parser.add_argument("sheet_id", help="Google Sheet ID")
    parser.add_argument("sheet_tab", help="Google Sheet tab name")

    add_validation_target_args(parser)
    args = parser.parse_args()
    table_name = args.table_name
    execution_date = args.execution_date
    environment = args.environment
    sheet_id = FORNO_SHEET_ID if environment == "forno" else args.sheet_id
    sheet_tab = args.sheet_tab
    database_name, read_table_name, _ = resolve_datalake_write_target(
        prod_database=SCHEMA,
        prod_table=table_name,
        prod_location="",
        bucket="",
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )

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

    gsheets_producer = _get_gsheets_writer(dbutils)
    spark_client = SparkClient()

    payload = _get_payloads_from_table(
        spark_client, read_table_name, execution_date, database_name
    )

    _write_payload_in_chunks(gsheets_producer, sheet_tab, sheet_id, payload)

    logger.info(
        "Export completed: table=%s, sheet=%s, tab=%s, rows=%d",
        table_name,
        sheet_id,
        sheet_tab,
        len(payload) - 1,
    )


if __name__ == "__main__":
    main()
