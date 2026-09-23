"""
Spark job that exports reverse Google Sheets tables to Google Sheets.

Reads from the reverse schema and writes to the specified Google Sheet.
Each table can target a different sheet (sheet_id) and tab (sheet_tab).
"""

import json
import time
from argparse import ArgumentParser
from datetime import datetime
from itertools import chain

import numpy as np
import pandas as pd
from gspread.exceptions import WorksheetNotFound
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient
from quintoandar_gsheets_api_client.producer import GoogleSheetsWriter
from quintoandar_logger import QuintoAndarLogger

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
logger = QuintoAndarLogger(JOB_NAME)

GSHEETS_WRITE_CHUNK_SIZE = 10_000
GSHEETS_GRID_ROW_BUFFER = 10
GSHEETS_CHUNK_PAUSE_SECONDS = 2
GSHEETS_SERVICE_ACCOUNT_EMAIL = (
    "gsheets-people-access@airflow-186119.iam.gserviceaccount.com"
)


def _is_not_found_gsheets_error(error: Exception) -> bool:
    """Return whether an exception is a 404 NOT_FOUND error."""
    error_msg = str(error).upper()
    if "404" in error_msg or "NOT_FOUND" in error_msg:
        return True
    if hasattr(error, "code") and error.code == 404:
        return True
    return hasattr(error, "resp") and getattr(error.resp, "status", None) == 404


def _is_workbook_cell_limit_error(error: Exception) -> bool:
    """Return whether the workbook hit Google's 10M cell limit."""
    error_msg = str(error).upper()
    return (
        "10000000" in error_msg
        or "10,000,000" in error_msg
        or "CELLS IN THE WORKBOOK" in error_msg
    )


def _is_missing_sheet_tab_error(error: Exception, sheet_tab: str) -> bool:
    """Return whether an exception indicates a missing sheet tab."""
    error_msg = str(error)
    if sheet_tab not in error_msg:
        return False
    return any(
        indicator in error_msg
        for indicator in (
            "Unable to parse range",
            "not found",
            "does not exist",
            "Invalid range",
            "No sheet",
        )
    )


def _raise_for_gsheets_error(error: Exception, sheet_tab: str) -> None:
    """Translate known Google Sheets failures into actionable errors."""
    error_msg = str(error)
    if _is_workbook_cell_limit_error(error):
        raise RuntimeError(
            "Google Sheets workbook cell limit exceeded (10M cells). "
            "Remove unused tabs, archive old data, or export to a dedicated spreadsheet."
        ) from error
    if _is_not_found_gsheets_error(error):
        raise RuntimeError(
            "Spreadsheet or sheet not found. Check sheet link and tab name."
        ) from error
    if _is_missing_sheet_tab_error(error, sheet_tab):
        raise RuntimeError(
            f"Sheet tab '{sheet_tab}' not found or invalid. Check tab name."
        ) from error
    if "PERMISSION_DENIED" in error_msg.upper():
        raise RuntimeError(
            "Bot does not have access to the gsheet. Share it with: "
            f"{GSHEETS_SERVICE_ACCOUNT_EMAIL}"
        ) from error


def _run_gsheets_operation(sheet_tab: str, operation, operation_label: str) -> None:
    """Run one Google Sheets API operation."""
    try:
        operation()
    except Exception as error:
        logger.error("GSheets %s failed: %s", operation_label, error)
        _raise_for_gsheets_error(error, sheet_tab)
        raise


def _pandas_dataframe_to_gsheets_rows(
    pandas_dataframe: pd.DataFrame, force_int_to_str: bool = False
) -> list:
    """Format a pandas DataFrame as rows with a header for the Sheets API."""
    for column in pandas_dataframe.columns:
        if pd.api.types.is_datetime64_any_dtype(pandas_dataframe[column]):
            if all(
                pandas_dataframe[column].dt.time == pd.to_datetime("00:00:00").time()
            ):
                pandas_dataframe[column] = pandas_dataframe[column].dt.strftime(
                    "%Y-%m-%d"
                )
            else:
                pandas_dataframe[column] = pandas_dataframe[column].dt.strftime(
                    "%Y-%m-%d %H:%M:%S"
                )
        if pandas_dataframe[column].dtype == "object":
            pandas_dataframe[column] = pandas_dataframe[column].astype(str)
            if any(
                value.startswith(("=", "+", "-", "@"))
                for value in pandas_dataframe[column]
            ):
                pandas_dataframe[column] = pandas_dataframe[column].apply(
                    lambda value: (
                        f"'{value}" if value.startswith(("=", "+", "-", "@")) else value
                    )
                )
        if force_int_to_str and not pd.api.types.is_float_dtype(
            pandas_dataframe[column]
        ):
            pandas_dataframe[column] = pandas_dataframe[column].apply(
                lambda value: "'" + str(value) if str(value).isdigit() else value
            )
    pandas_dataframe = pandas_dataframe.replace(
        [np.inf, -np.inf, np.nan, pd.NaT, None, "None", "nan", "'None", "'nan"],
        "",
    )
    rows = pandas_dataframe.values.tolist()
    rows.insert(0, pandas_dataframe.columns.tolist())
    return rows


def _spark_dataframe_to_gsheets_rows(dataframe, force_int_to_str: bool = False) -> list:
    """Format a Spark DataFrame as rows with a header for the Sheets API."""
    return _pandas_dataframe_to_gsheets_rows(
        dataframe.toPandas(), force_int_to_str=force_int_to_str
    )


def _iter_payload_write_chunks(payload: list, chunk_size: int) -> list[list]:
    """Split payload into write batches, keeping the header in the first batch."""
    if not payload:
        return []
    header = payload[0]
    data_rows = payload[1:]
    if not data_rows:
        return [[header]]
    chunks = []
    for start in range(0, len(data_rows), chunk_size):
        batch = data_rows[start : start + chunk_size]
        chunks.append([header] + batch if start == 0 else batch)
    return chunks


def _iter_payloads_from_table(
    spark_client: SparkClient,
    table_name: str,
    execution_date: str,
    database_name: str = SCHEMA,
    chunk_size: int = GSHEETS_WRITE_CHUNK_SIZE,
):
    """Stream table rows in bounded batches formatted for the Sheets API."""
    execution_dt = datetime.strptime(execution_date, "%Y-%m-%d")
    query = f"""
        SELECT *
        FROM {database_name}.{table_name}
        WHERE year = {execution_dt.year}
          AND month = {execution_dt.month}
          AND day = {execution_dt.day}
    """
    dataframe = spark_client.get_records(query)
    output_columns = [
        column for column in dataframe.columns if column not in {"year", "month", "day"}
    ]
    yield output_columns

    selected_dataframe = dataframe.select(output_columns)
    rows = []
    for row in selected_dataframe.toLocalIterator():
        rows.append(row.asDict(recursive=True))
        if len(rows) == chunk_size:
            formatted_rows = _pandas_dataframe_to_gsheets_rows(
                pd.DataFrame.from_records(rows, columns=output_columns)
            )
            yield formatted_rows[1:]
            rows = []
    if rows:
        formatted_rows = _pandas_dataframe_to_gsheets_rows(
            pd.DataFrame.from_records(rows, columns=output_columns)
        )
        yield formatted_rows[1:]


def _get_worksheet(writer: GoogleSheetsWriter, sheet_id: str, sheet_tab: str):
    """Return a worksheet handle, creating the tab when needed."""
    workbook = writer.google_sheets_client.gsheets.open_by_key(sheet_id)
    try:
        return workbook.worksheet(sheet_tab)
    except WorksheetNotFound:
        logger.warning(
            "Sheet tab '%s' not found in spreadsheet %s; creating it",
            sheet_tab,
            sheet_id,
        )
        return workbook.add_worksheet(title=sheet_tab, rows=1, cols=1)


def _grow_worksheet_grid(worksheet, n_rows: int, n_cols: int) -> None:
    """Expand the worksheet grid before writing payload data."""
    target_rows = max(n_rows, 1)
    target_cols = max(n_cols, 1)
    if worksheet.row_count >= target_rows and worksheet.col_count >= target_cols:
        return
    worksheet.resize(
        rows=max(worksheet.row_count, target_rows),
        cols=max(worksheet.col_count, target_cols),
    )


def _write_payload_in_chunks(
    writer: GoogleSheetsWriter,
    sheet_tab: str,
    sheet_id: str,
    payload: list,
    chunk_size: int = GSHEETS_WRITE_CHUNK_SIZE,
) -> None:
    """Replace worksheet content in chunks to avoid Sheets API limits."""
    if not payload:
        return
    chunks = _iter_payload_write_chunks(payload, chunk_size)
    worksheet = _get_worksheet(writer, sheet_id, sheet_tab)
    _run_gsheets_operation(
        sheet_tab,
        lambda: _grow_worksheet_grid(
            worksheet, len(payload) + GSHEETS_GRID_ROW_BUFFER, len(payload[0])
        ),
        "resize grid",
    )
    _run_gsheets_operation(sheet_tab, worksheet.clear, "clear")
    start_row = 1
    for chunk_index, chunk in enumerate(chunks, start=1):
        range_a1 = f"A{start_row}"
        _run_gsheets_operation(
            sheet_tab,
            lambda values=chunk, cell_range=range_a1: worksheet.update(
                cell_range, values, raw=False
            ),
            f"update chunk {chunk_index}/{len(chunks)} ({range_a1})",
        )
        start_row += len(chunk)
        if chunk_index < len(chunks):
            time.sleep(GSHEETS_CHUNK_PAUSE_SECONDS)


def _write_payload_streaming(
    writer: GoogleSheetsWriter,
    sheet_tab: str,
    sheet_id: str,
    payload_chunks,
) -> None:
    """Write bounded payload chunks without collecting the full table."""
    payload_chunks = iter(payload_chunks)
    try:
        header = next(payload_chunks)
    except StopIteration:
        return

    worksheet = _get_worksheet(writer, sheet_id, sheet_tab)
    _run_gsheets_operation(sheet_tab, worksheet.clear, "clear")

    start_row = 1
    first_data_chunk = next(payload_chunks, None)
    chunks = iter(
        [first_data_chunk]
        if first_data_chunk is None
        else chain([first_data_chunk], payload_chunks)
    )
    for chunk_index, rows in enumerate(chunks, start=1):
        rows = rows or []
        chunk = [header] + rows if start_row == 1 else rows
        _run_gsheets_operation(
            sheet_tab,
            lambda row_count=start_row + len(chunk) + GSHEETS_GRID_ROW_BUFFER: (
                _grow_worksheet_grid(worksheet, row_count, len(header))
            ),
            f"resize grid before chunk {chunk_index}",
        )
        range_a1 = f"A{start_row}"
        _run_gsheets_operation(
            sheet_tab,
            lambda values=chunk, cell_range=range_a1: worksheet.update(
                cell_range, values, raw=False
            ),
            f"update chunk {chunk_index} ({range_a1})",
        )
        start_row += len(chunk)
        if len(rows) == GSHEETS_WRITE_CHUNK_SIZE:
            time.sleep(GSHEETS_CHUNK_PAUSE_SECONDS)


def _get_auth(dbutils, credentials_scope: str, credentials_key: str):
    """Retrieve Google Sheets credentials from Databricks secrets."""
    credentials = json.loads(
        dbutils.secrets.get(scope=credentials_scope, key=credentials_key)
    )
    credentials.pop("scope", None)
    return credentials, "https://www.googleapis.com/auth/spreadsheets"


def _get_gsheets_writer(dbutils) -> GoogleSheetsWriter:
    """Return a GoogleSheetsWriter configured with People credentials."""
    credentials, scope = _get_auth(
        dbutils, CREDENTIALS_SCOPE, APIEnum.GSHEETS_CREDENTIALS_PEOPLE
    )
    return GoogleSheetsWriter(GoogleSheetsClient(credentials, scope))


def _get_payloads_from_table(
    spark_client: SparkClient,
    table_name: str,
    execution_date: str,
    database_name: str = SCHEMA,
) -> list:
    """Fetch one reverse table partition and format it for Google Sheets."""
    execution_dt = datetime.strptime(execution_date, "%Y-%m-%d")
    query = f"""
        SELECT *
        FROM {database_name}.{table_name}
        WHERE year = {execution_dt.year}
          AND month = {execution_dt.month}
          AND day = {execution_dt.day}
    """
    dataframe = spark_client.get_records(query)
    output_columns = [
        column for column in dataframe.columns if column not in {"year", "month", "day"}
    ]
    return _spark_dataframe_to_gsheets_rows(dataframe.select(output_columns))


def main():
    """Export one reverse table to a Google Sheet."""
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("environment")
    parser.add_argument("sheet_id")
    parser.add_argument("sheet_tab")
    add_validation_target_args(parser)
    args = parser.parse_args()

    sheet_id = FORNO_SHEET_ID if args.environment == "forno" else args.sheet_id
    database_name, read_table_name, _ = resolve_datalake_write_target(
        prod_database=SCHEMA,
        prod_table=args.table_name,
        prod_location="",
        bucket="",
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    dbutils = BaseDBUtils().get_dbutils()
    if dbutils is None:
        raise RuntimeError("DBUtils not available. This job must run on Databricks.")

    payload_chunks = _iter_payloads_from_table(
        SparkClient(app_name=JOB_NAME),
        read_table_name,
        args.execution_date,
        database_name,
    )
    _write_payload_streaming(
        _get_gsheets_writer(dbutils),
        args.sheet_tab,
        sheet_id,
        payload_chunks,
    )


if __name__ == "__main__":
    main()
