"""
Unit tests for load_to_gsheet Spark job.

Tests the export of reverse_reports tables to Google Sheets through the main
entry point, with mocked dbutils, SparkClient, and Google Sheets API clients.
"""

import json
import unittest
from datetime import date, datetime
from decimal import Decimal
from unittest.mock import MagicMock, patch

from dags.people.reverse_reports.spark_jobs import load_to_gsheet as job
from tests.dags.people.reverse_reports.spark_jobs.conftest import (
    MOCK_WORKSHEET_NOT_FOUND,
)

MODULE_UNDER_TEST = "dags.people.reverse_reports.spark_jobs.load_to_gsheet"


class TestCellValueToStr(unittest.TestCase):
    """Tests for _cell_value_to_str helper."""

    def test_none_returns_empty_string(self):
        self.assertEqual(job._cell_value_to_str(None), "")

    def test_decimal_returns_string(self):
        self.assertEqual(job._cell_value_to_str(Decimal("1234.56")), "1234.56")

    def test_date_returns_iso_format(self):
        self.assertEqual(job._cell_value_to_str(date(2025, 3, 12)), "2025-03-12")

    def test_datetime_date_only_returns_iso_date(self):
        self.assertEqual(
            job._cell_value_to_str(datetime(2025, 3, 12, 0, 0, 0)),
            "2025-03-12",
        )

    def test_datetime_with_time_returns_iso_datetime(self):
        self.assertEqual(
            job._cell_value_to_str(datetime(2025, 3, 12, 10, 30, 0)),
            "2025-03-12 10:30:00",
        )

    def test_bool_returns_yes_no(self):
        self.assertEqual(job._cell_value_to_str(True), "Yes")
        self.assertEqual(job._cell_value_to_str(False), "No")

    def test_nan_returns_empty_string(self):
        self.assertEqual(job._cell_value_to_str(float("nan")), "")

    def test_inf_returns_empty_string(self):
        self.assertEqual(job._cell_value_to_str(float("inf")), "")
        self.assertEqual(job._cell_value_to_str(float("-inf")), "")

    def test_formula_prefix_escaped(self):
        self.assertEqual(job._cell_value_to_str("=SUM(A1)"), "'=SUM(A1)")
        self.assertEqual(job._cell_value_to_str("+123"), "'+123")

    def test_plain_string_unchanged(self):
        self.assertEqual(job._cell_value_to_str("hello"), "hello")
        self.assertEqual(job._cell_value_to_str(42), "42")


class TestIsRetriableGsheetsError(unittest.TestCase):
    """Tests for _is_retriable_gsheets_error helper."""

    def test_429_is_retriable(self):
        self.assertTrue(
            job._is_retriable_gsheets_error(Exception("429 Too Many Requests"))
        )

    def test_503_is_retriable(self):
        self.assertTrue(
            job._is_retriable_gsheets_error(Exception("503 Service Unavailable"))
        )

    def test_resource_exhausted_is_retriable(self):
        self.assertTrue(
            job._is_retriable_gsheets_error(Exception("RESOURCE_EXHAUSTED"))
        )

    def test_404_is_not_retriable(self):
        self.assertFalse(job._is_retriable_gsheets_error(Exception("404 NOT_FOUND")))

    def test_permission_denied_is_not_retriable(self):
        self.assertFalse(
            job._is_retriable_gsheets_error(Exception("PERMISSION_DENIED"))
        )


class TestWriteWithRetries(unittest.TestCase):
    """Tests for _write_with_retries helper."""

    def test_succeeds_on_first_try(self):
        mock_writer = MagicMock()
        job._write_with_retries(mock_writer, "Tab", "sheet-id", [["a"], ["b"]])

        mock_writer.write.assert_called_once_with("Tab", "sheet-id", [["a"], ["b"]])

    @patch(f"{MODULE_UNDER_TEST}.time.sleep")
    def test_retries_on_429_then_succeeds(self, mock_sleep):
        mock_writer = MagicMock()
        mock_writer.write.side_effect = [Exception("429"), None]

        job._write_with_retries(mock_writer, "Tab", "sheet-id", [["a"]])

        self.assertEqual(mock_writer.write.call_count, 2)
        mock_sleep.assert_called_once_with(job.WRITE_RETRY_DELAYS_SECONDS[0])

    @patch(f"{MODULE_UNDER_TEST}.time.sleep")
    def test_raises_after_all_retries_exhausted(self, mock_sleep):
        mock_writer = MagicMock()
        mock_writer.write.side_effect = Exception("429")

        with self.assertRaises(RuntimeError) as ctx:
            job._write_with_retries(mock_writer, "Tab", "sheet-id", [["a"]])

        self.assertIn("429", str(ctx.exception))
        self.assertEqual(
            mock_writer.write.call_count,
            len(job.WRITE_RETRY_DELAYS_SECONDS) + 1,
        )

    def test_fails_immediately_on_404(self):
        mock_writer = MagicMock()
        mock_writer.write.side_effect = Exception("404 NOT_FOUND")

        with self.assertRaises(RuntimeError) as ctx:
            job._write_with_retries(mock_writer, "Tab", "sheet-id", [["a"]])

        self.assertIn("not found", str(ctx.exception).lower())
        mock_writer.write.assert_called_once()

    def test_fails_immediately_on_permission_denied(self):
        mock_writer = MagicMock()
        mock_writer.write.side_effect = Exception("PERMISSION_DENIED")

        with self.assertRaises(RuntimeError) as ctx:
            job._write_with_retries(mock_writer, "Tab", "sheet-id", [["a"]])

        self.assertIn("gsheets-people-access", str(ctx.exception))
        mock_writer.write.assert_called_once()


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

    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    def test_returns_header_and_rows_excluding_partition_cols(
        self, mock_spark_client_cls
    ):
        mock_spark_client = MagicMock()
        mock_spark_client_cls.return_value = mock_spark_client

        mock_df = MagicMock()
        mock_df.columns = ["id_user", "user_name", "year", "month", "day"]
        mock_df.select.return_value.rdd.map.return_value.collect.return_value = [
            ["1", "Alice"],
            ["2", "Bob"],
        ]
        mock_spark_client.get_records.return_value = mock_df

        header, rows = job._get_payloads_from_table(
            mock_spark_client, "jobs", "2025-03-12"
        )

        self.assertEqual(header, ["id_user", "user_name"])
        self.assertEqual(rows, [["1", "Alice"], ["2", "Bob"]])
        mock_spark_client.get_records.assert_called_once()
        call_args = mock_spark_client.get_records.call_args[0][0]
        self.assertIn("reverse_reports.jobs", call_args)
        self.assertIn("year = 2025", call_args)
        self.assertIn("month = 3", call_args)
        self.assertIn("day = 12", call_args)

    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    def test_converts_none_to_empty_string(self, mock_spark_client_cls):
        mock_spark_client = MagicMock()
        mock_spark_client_cls.return_value = mock_spark_client

        mock_df = MagicMock()
        mock_df.columns = ["id_user", "user_name"]
        raw_rows = [["1", None]]

        def collect_applies_conversion():
            return [[str(x) if x is not None else "" for x in row] for row in raw_rows]

        mock_rdd = MagicMock()
        mock_rdd.map.return_value.collect.side_effect = collect_applies_conversion
        mock_df.select.return_value.rdd = mock_rdd
        mock_spark_client.get_records.return_value = mock_df

        _, rows = job._get_payloads_from_table(mock_spark_client, "jobs", "2025-03-12")

        self.assertEqual(rows, [["1", ""]])


class TestEnsureWorksheetExists(unittest.TestCase):
    """Tests for _ensure_worksheet_exists helper."""

    @patch(f"{MODULE_UNDER_TEST}.gspread")
    @patch(f"{MODULE_UNDER_TEST}.ServiceAccountCredentials")
    def test_does_not_create_when_worksheet_exists(self, mock_creds_cls, mock_gspread):
        mock_spreadsheet = MagicMock()
        mock_gspread.authorize.return_value.open_by_key.return_value = mock_spreadsheet
        mock_spreadsheet.worksheet.return_value = MagicMock()

        job._ensure_worksheet_exists(
            {"type": "service_account"}, "https://scope", "sheet-id", "Tab1"
        )

        mock_spreadsheet.add_worksheet.assert_not_called()

    @patch(f"{MODULE_UNDER_TEST}.gspread")
    @patch(f"{MODULE_UNDER_TEST}.ServiceAccountCredentials")
    def test_creates_worksheet_when_not_found(self, mock_creds_cls, mock_gspread):
        mock_spreadsheet = MagicMock()
        mock_spreadsheet.worksheet.side_effect = MOCK_WORKSHEET_NOT_FOUND("Tab1")
        mock_gspread.authorize.return_value.open_by_key.return_value = mock_spreadsheet

        job._ensure_worksheet_exists(
            {"type": "service_account"}, "https://scope", "sheet-id", "Tab1"
        )

        mock_spreadsheet.add_worksheet.assert_called_once_with(
            title="Tab1", rows=1000, cols=26
        )


class TestMain(unittest.TestCase):
    """Tests for main entry point with full mocks."""

    @patch(f"{MODULE_UNDER_TEST}.GoogleSheetsWriter")
    @patch(f"{MODULE_UNDER_TEST}.GoogleSheetsClient")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_main_success_prod_environment(
        self,
        mock_base_dbutils,
        mock_spark_cls,
        mock_gsheets_client_cls,
        mock_writer_cls,
    ):
        mock_dbutils = MagicMock()
        mock_dbutils.secrets.get.return_value = json.dumps(
            {"type": "service_account", "project_id": "test"}
        )
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils

        mock_spark_client = MagicMock()
        mock_spark_cls.return_value = mock_spark_client
        mock_df = MagicMock()
        mock_df.columns = ["id_user", "user_name"]
        mock_df.select.return_value.rdd.map.return_value.collect.return_value = [
            ["1", "Alice"],
        ]
        mock_spark_client.get_records.return_value = mock_df

        mock_writer = MagicMock()
        mock_writer_cls.return_value = mock_writer

        with patch.object(job, "_ensure_worksheet_exists"):
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

        mock_writer.write.assert_called_once_with(
            "JobsTab",
            "prod-sheet-id-123",
            [
                ["id_user", "user_name"],
                ["1", "Alice"],
            ],
        )

    @patch(f"{MODULE_UNDER_TEST}.GoogleSheetsWriter")
    @patch(f"{MODULE_UNDER_TEST}.GoogleSheetsClient")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_main_uses_forno_sheet_id_when_environment_forno(
        self,
        mock_base_dbutils,
        mock_spark_cls,
        mock_gsheets_client_cls,
        mock_writer_cls,
    ):
        mock_dbutils = MagicMock()
        mock_dbutils.secrets.get.return_value = json.dumps(
            {"type": "service_account", "project_id": "test"}
        )
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils

        mock_spark_client = MagicMock()
        mock_spark_cls.return_value = mock_spark_client
        mock_df = MagicMock()
        mock_df.columns = ["col_a"]
        mock_df.select.return_value.rdd.map.return_value.collect.return_value = []
        mock_spark_client.get_records.return_value = mock_df

        mock_writer = MagicMock()
        mock_writer_cls.return_value = mock_writer

        with patch.object(job, "_ensure_worksheet_exists"):
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

        mock_writer.write.assert_called_once()
        call_args = mock_writer.write.call_args[0]
        self.assertEqual(call_args[1], job.FORNO_SHEET_ID)
        self.assertEqual(call_args[0], "SalaryTab")

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
