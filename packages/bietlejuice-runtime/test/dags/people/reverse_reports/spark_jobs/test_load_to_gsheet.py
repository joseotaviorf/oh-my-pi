"""
Unit tests for load_to_gsheet Spark job.

Tests the export of reverse_reports tables to Google Sheets through the main
entry point, with mocked dbutils, SparkClient, and Google Sheets API clients.
"""

import json
import unittest
from unittest.mock import MagicMock, call, patch

import numpy as np
import pandas as pd

from dags.people.reverse_reports.spark_jobs import load_to_gsheet as job

MODULE_UNDER_TEST = "dags.people.reverse_reports.spark_jobs.load_to_gsheet"


class TestSparkDataframeToGsheetsRows(unittest.TestCase):
    """Tests for _spark_dataframe_to_gsheets_rows helper."""

    def test_formats_datetime_date_only(self):
        mock_df = MagicMock()
        mock_df.toPandas.return_value = pd.DataFrame(
            {"dt": pd.to_datetime(["2025-03-12"])},
        )

        rows = job._spark_dataframe_to_gsheets_rows(mock_df)

        self.assertEqual(rows[0], ["dt"])
        self.assertEqual(rows[1], ["2025-03-12"])

    def test_escapes_formula_prefix_in_object_columns(self):
        mock_df = MagicMock()
        mock_df.toPandas.return_value = pd.DataFrame(
            {"val": pd.Series(["=SUM(A1)", "ok"], dtype=object)}
        )

        rows = job._spark_dataframe_to_gsheets_rows(mock_df)

        self.assertEqual(rows[1][0], "'=SUM(A1)")
        self.assertEqual(rows[2][0], "ok")

    def test_replaces_nan_and_none_with_empty_string(self):
        mock_df = MagicMock()
        mock_df.toPandas.return_value = pd.DataFrame({"val": [None, np.nan]})

        rows = job._spark_dataframe_to_gsheets_rows(mock_df)

        self.assertEqual(rows[1][0], "")
        self.assertEqual(rows[2][0], "")

    def test_bool_values_kept_as_native_types(self):
        mock_df = MagicMock()
        mock_df.toPandas.return_value = pd.DataFrame({"flag": [True, False]})

        rows = job._spark_dataframe_to_gsheets_rows(mock_df)

        self.assertEqual(rows[1][0], True)
        self.assertEqual(rows[2][0], False)


class TestGSheetsErrorClassification(unittest.TestCase):
    """Tests for GSheets error classification helpers."""

    def test_workbook_cell_limit_is_detected(self):
        error = Exception(
            "{'code': 400, 'message': 'This action would increase the number of "
            "cells in the workbook above the limit of 10000000 cells.', "
            "'status': 'INVALID_ARGUMENT'}"
        )
        self.assertTrue(job._is_workbook_cell_limit_error(error))

    def test_404_is_not_found(self):
        self.assertTrue(job._is_not_found_gsheets_error(Exception("404 NOT_FOUND")))

    def test_cell_limit_raises_actionable_runtime_error(self):
        error = Exception(
            "400 INVALID_ARGUMENT: cells in the workbook above the limit of 10000000 cells"
        )
        with self.assertRaises(RuntimeError) as ctx:
            job._raise_for_gsheets_error(error, "Tab")

        self.assertIn("10M cells", str(ctx.exception))

    def test_permission_denied_raises_actionable_runtime_error(self):
        with self.assertRaises(RuntimeError) as ctx:
            job._raise_for_gsheets_error(Exception("PERMISSION_DENIED"), "Tab")

        self.assertIn("gsheets-people-access", str(ctx.exception))


class TestIterPayloadWriteChunks(unittest.TestCase):
    """Tests for _iter_payload_write_chunks helper."""

    def test_header_only(self):
        chunks = job._iter_payload_write_chunks([["h1", "h2"]], chunk_size=2)
        self.assertEqual(chunks, [[["h1", "h2"]]])

    def test_splits_data_rows_and_keeps_header_in_first_chunk(self):
        payload = [["h"], ["1"], ["2"], ["3"], ["4"], ["5"]]
        chunks = job._iter_payload_write_chunks(payload, chunk_size=2)

        self.assertEqual(chunks, [[["h"], ["1"], ["2"]], [["3"], ["4"]], [["5"]]])


class TestGetWorksheet(unittest.TestCase):
    """Tests for _get_worksheet helper."""

    def test_returns_existing_worksheet(self):
        mock_writer = MagicMock()
        mock_workbook = MagicMock()
        mock_worksheet = MagicMock()
        mock_writer.google_sheets_client.gsheets.open_by_key.return_value = (
            mock_workbook
        )
        mock_workbook.worksheet.return_value = mock_worksheet

        result = job._get_worksheet(mock_writer, "sheet-id", "Tab")

        self.assertEqual(result, mock_worksheet)
        mock_workbook.worksheet.assert_called_once_with("Tab")
        mock_workbook.add_worksheet.assert_not_called()

    def test_creates_worksheet_when_tab_missing(self):
        mock_writer = MagicMock()
        mock_workbook = MagicMock()
        mock_worksheet = MagicMock()
        mock_writer.google_sheets_client.gsheets.open_by_key.return_value = (
            mock_workbook
        )
        mock_workbook.worksheet.side_effect = job.WorksheetNotFound("ALL5A1")
        mock_workbook.add_worksheet.return_value = mock_worksheet

        result = job._get_worksheet(mock_writer, "sheet-id", "ALL5A1")

        self.assertEqual(result, mock_worksheet)
        mock_workbook.add_worksheet.assert_called_once_with(
            title="ALL5A1",
            rows=1,
            cols=1,
        )


class TestWritePayloadInChunks(unittest.TestCase):
    """Tests for _write_payload_in_chunks helper."""

    def _build_writer_with_worksheet(self):
        mock_writer = MagicMock()
        mock_workbook = MagicMock()
        mock_worksheet = MagicMock()
        mock_writer.google_sheets_client.gsheets.open_by_key.return_value = (
            mock_workbook
        )
        mock_workbook.worksheet.return_value = mock_worksheet
        return mock_writer, mock_worksheet

    def test_small_payload_grows_grid_and_updates_from_a1(self):
        mock_writer, mock_worksheet = self._build_writer_with_worksheet()
        mock_worksheet.row_count = 1_000
        mock_worksheet.col_count = 26
        payload = [["h"], ["1"], ["2"]]

        job._write_payload_in_chunks(
            mock_writer, "Tab", "sheet-id", payload, chunk_size=10_000
        )

        mock_writer.write.assert_not_called()
        mock_worksheet.append_rows.assert_not_called()
        mock_worksheet.clear.assert_called_once()
        mock_worksheet.update.assert_called_once_with("A1", payload, raw=False)

    def test_grows_grid_when_below_payload_size(self):
        mock_writer, mock_worksheet = self._build_writer_with_worksheet()
        mock_worksheet.row_count = 1_000
        mock_worksheet.col_count = 26

        job._grow_worksheet_grid(mock_worksheet, n_rows=10_210, n_cols=42)

        mock_worksheet.resize.assert_called_once_with(rows=10_210, cols=42)

    def test_does_not_shrink_existing_grid(self):
        mock_writer, mock_worksheet = self._build_writer_with_worksheet()
        mock_worksheet.row_count = 50_000
        mock_worksheet.col_count = 50

        job._grow_worksheet_grid(mock_worksheet, n_rows=10_210, n_cols=42)

        mock_worksheet.resize.assert_not_called()

    @patch(f"{MODULE_UNDER_TEST}.time.sleep")
    def test_large_payload_resizes_then_updates_chunks_by_range(self, mock_sleep):
        mock_writer, mock_worksheet = self._build_writer_with_worksheet()
        mock_worksheet.row_count = 1_000
        mock_worksheet.col_count = 26
        chunk_size = 2
        payload = [["h"], ["1"], ["2"], ["3"], ["4"], ["5"]]

        job._write_payload_in_chunks(
            mock_writer, "Tab", "sheet-id", payload, chunk_size=chunk_size
        )

        mock_writer.write.assert_not_called()
        mock_worksheet.resize.assert_not_called()
        mock_worksheet.clear.assert_called_once()
        mock_worksheet.update.assert_has_calls(
            [
                call("A1", [["h"], ["1"], ["2"]], raw=False),
                call("A4", [["3"], ["4"]], raw=False),
                call("A6", [["5"]], raw=False),
            ]
        )
        # load_to_gsheet.time.sleep is stdlib time.sleep; ignore Spark thread calls.
        pause_calls = [
            c
            for c in mock_sleep.call_args_list
            if c == call(job.GSHEETS_CHUNK_PAUSE_SECONDS)
        ]
        self.assertEqual(len(pause_calls), 2)

    def test_payload_just_over_10k_uses_range_updates_not_append(self):
        mock_writer, mock_worksheet = self._build_writer_with_worksheet()
        mock_worksheet.row_count = 10_000
        mock_worksheet.col_count = 26
        payload = [["h"]] + [[str(i)] for i in range(10_001)]

        job._write_payload_in_chunks(
            mock_writer, "Tab", "sheet-id", payload, chunk_size=10_000
        )

        mock_writer.write.assert_not_called()
        mock_worksheet.append_rows.assert_not_called()
        mock_worksheet.resize.assert_called_once_with(rows=10_012, cols=26)
        self.assertEqual(mock_worksheet.update.call_count, 2)
        first_call = mock_worksheet.update.call_args_list[0]
        second_call = mock_worksheet.update.call_args_list[1]
        self.assertEqual(first_call.args[0], "A1")
        self.assertEqual(len(first_call.args[1]), 10_001)
        self.assertEqual(second_call.args[0], "A10002")
        self.assertEqual(second_call.args[1], [["10000"]])

    def test_cell_limit_fails_fast_without_retry(self):
        mock_writer, mock_worksheet = self._build_writer_with_worksheet()
        mock_worksheet.row_count = 1_000
        mock_worksheet.col_count = 26
        mock_worksheet.update.side_effect = Exception(
            "400 INVALID_ARGUMENT: cells in the workbook above the limit of 10000000 cells"
        )

        with self.assertRaises(RuntimeError) as ctx:
            job._write_payload_in_chunks(
                mock_writer, "Tab", "sheet-id", [["h"], ["1"]], chunk_size=10_000
            )

        self.assertIn("10M cells", str(ctx.exception))
        mock_worksheet.update.assert_called_once()


class TestGetAuth(unittest.TestCase):
    """Tests for _get_auth helper."""

    def test_returns_credentials_and_scope(self):
        dbutils = MagicMock()
        creds_dict = {"type": "service_account", "project_id": "test", "scope": "old"}
        dbutils.secrets.get.return_value = json.dumps(creds_dict)

        credentials, scope = job._get_auth(
            dbutils, "people", "GOOGLE_SERVICE_ACCOUNT_CREDENTIALS_PEOPLE"
        )

        self.assertEqual(scope, "https://www.googleapis.com/auth/spreadsheets")
        self.assertNotIn("scope", credentials)
        self.assertEqual(credentials["type"], "service_account")
        dbutils.secrets.get.assert_called_once_with(
            scope="people", key="GOOGLE_SERVICE_ACCOUNT_CREDENTIALS_PEOPLE"
        )

    def test_pops_scope_from_credentials(self):
        dbutils = MagicMock()
        creds_dict = {"type": "service_account", "scope": "unwanted"}
        dbutils.secrets.get.return_value = json.dumps(creds_dict)

        credentials, _ = job._get_auth(dbutils, "people", "key")

        self.assertNotIn("scope", credentials)


class TestGetPayloadsFromTable(unittest.TestCase):
    """Tests for _get_payloads_from_table helper."""

    @patch(f"{MODULE_UNDER_TEST}._spark_dataframe_to_gsheets_rows")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    def test_returns_payload_excluding_partition_cols(
        self, mock_spark_client_cls, mock_format_rows
    ):
        mock_spark_client = MagicMock()
        mock_spark_client_cls.return_value = mock_spark_client

        mock_df = MagicMock()
        mock_df.columns = ["id_user", "user_name", "year", "month", "day"]
        mock_selected = MagicMock()
        mock_df.select.return_value = mock_selected
        mock_spark_client.get_records.return_value = mock_df
        mock_format_rows.return_value = [
            ["id_user", "user_name"],
            ["1", "Alice"],
            ["2", "Bob"],
        ]

        payload = job._get_payloads_from_table(mock_spark_client, "jobs", "2025-03-12")

        self.assertEqual(
            payload,
            [
                ["id_user", "user_name"],
                ["1", "Alice"],
                ["2", "Bob"],
            ],
        )
        mock_df.select.assert_called_once_with(["id_user", "user_name"])
        mock_format_rows.assert_called_once_with(mock_selected)
        mock_spark_client.get_records.assert_called_once()
        call_args = mock_spark_client.get_records.call_args[0][0]
        self.assertIn("reverse_reports.jobs", call_args)
        self.assertIn("year = 2025", call_args)
        self.assertIn("month = 3", call_args)
        self.assertIn("day = 12", call_args)


class TestMain(unittest.TestCase):
    """Tests for main entry point with full mocks."""

    @patch(f"{MODULE_UNDER_TEST}._write_payload_in_chunks")
    @patch(f"{MODULE_UNDER_TEST}._get_gsheets_writer")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_main_success_prod_environment(
        self,
        mock_base_dbutils,
        mock_spark_cls,
        mock_get_writer,
        mock_write_chunks,
    ):
        mock_dbutils = MagicMock()
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils

        mock_spark_client = MagicMock()
        mock_spark_cls.return_value = mock_spark_client

        mock_writer = MagicMock()
        mock_get_writer.return_value = mock_writer

        payload = [["id_user", "user_name"], ["1", "Alice"]]
        with patch.object(
            job,
            "_get_payloads_from_table",
            return_value=payload,
        ):
            with patch(
                "sys.argv",
                [
                    "script",
                    "jobs",
                    "2025-03-12",
                    "prod",
                    "prod-sheet-id-123",
                    "JobsTab",
                ],
            ):
                job.main()

        mock_get_writer.assert_called_once_with(mock_dbutils)
        mock_write_chunks.assert_called_once_with(
            mock_writer,
            "JobsTab",
            "prod-sheet-id-123",
            payload,
        )

    @patch(f"{MODULE_UNDER_TEST}._write_payload_in_chunks")
    @patch(f"{MODULE_UNDER_TEST}._get_gsheets_writer")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_main_uses_forno_sheet_id_when_environment_forno(
        self,
        mock_base_dbutils,
        mock_spark_cls,
        mock_get_writer,
        mock_write_chunks,
    ):
        mock_dbutils = MagicMock()
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils

        mock_spark_client = MagicMock()
        mock_spark_cls.return_value = mock_spark_client

        mock_writer = MagicMock()
        mock_get_writer.return_value = mock_writer

        with patch.object(
            job,
            "_get_payloads_from_table",
            return_value=[["col_a"], ["x"]],
        ):
            with patch(
                "sys.argv",
                [
                    "script",
                    "salary_tables",
                    "2025-03-12",
                    "forno",
                    "ignored-sheet-id",
                    "SalaryTab",
                ],
            ):
                job.main()

        mock_write_chunks.assert_called_once()
        call_args = mock_write_chunks.call_args[0]
        self.assertEqual(call_args[2], job.FORNO_SHEET_ID)
        self.assertEqual(call_args[1], "SalaryTab")

    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_main_raises_when_dbutils_unavailable(self, mock_base_dbutils):
        mock_base_dbutils.return_value.get_dbutils.return_value = None

        with patch(
            "sys.argv", ["script", "jobs", "2025-03-12", "prod", "sheet-id", "Tab"]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                job.main()

        self.assertIn("DBUtils", str(ctx.exception))
        self.assertIn("Databricks", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
