"""
Unit tests for load_to_gsheet Spark job.

Tests the export of reverse_reports tables to Google Sheets through the main
entry point, with mocked dbutils, SparkClient, and Google Sheets API clients.
"""

import json
import unittest
from unittest.mock import MagicMock, patch

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

    def test_500_is_retriable(self):
        self.assertTrue(
            job._is_retriable_gsheets_error(Exception("500 Internal Server Error"))
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

    @patch(f"{MODULE_UNDER_TEST}.time.sleep")
    def test_retries_on_500_when_sheet_id_in_error_message(self, mock_sleep):
        mock_writer = MagicMock()
        mock_writer.write.side_effect = [
            Exception(
                "500 Internal Server Error: "
                "https://sheets.googleapis.com/v4/spreadsheets/bad-sheet-id"
            ),
            None,
        ]

        job._write_with_retries(mock_writer, "Tab", "bad-sheet-id", [["a"]])

        self.assertEqual(mock_writer.write.call_count, 2)
        mock_sleep.assert_called_once_with(job.WRITE_RETRY_DELAYS_SECONDS[0])


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

    @patch(f"{MODULE_UNDER_TEST}._get_gsheets_writer")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_main_success_prod_environment(
        self,
        mock_base_dbutils,
        mock_spark_cls,
        mock_get_writer,
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
            return_value=[["id_user", "user_name"], ["1", "Alice"]],
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
        mock_writer.write.assert_called_once_with(
            "JobsTab",
            "prod-sheet-id-123",
            [
                ["id_user", "user_name"],
                ["1", "Alice"],
            ],
        )

    @patch(f"{MODULE_UNDER_TEST}._get_gsheets_writer")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_main_uses_forno_sheet_id_when_environment_forno(
        self,
        mock_base_dbutils,
        mock_spark_cls,
        mock_get_writer,
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
