"""Unit tests for the shared reverse Google Sheets Spark job."""

import unittest
from unittest.mock import MagicMock, call, patch

import pandas as pd

from dags.people.reverse_gsheets_shared.spark_jobs import load_to_gsheet as job

MODULE_UNDER_TEST = "dags.people.reverse_gsheets_shared.spark_jobs.load_to_gsheet"


class TestPandasDataframeToGsheetsRows(unittest.TestCase):
    """Tests for DataFrame formatting before writing to Google Sheets."""

    def test_escapes_all_formula_prefixes(self):
        dataframe = pd.DataFrame(
            {
                "value": pd.Series(
                    ["=SUM(A1)", "+1", "-1+2", "@NOW()", "plain"],
                    dtype=object,
                )
            }
        )

        rows = job._pandas_dataframe_to_gsheets_rows(dataframe)

        self.assertEqual(
            rows,
            [
                ["value"],
                ["'=SUM(A1)"],
                ["'+1"],
                ["'-1+2"],
                ["'@NOW()"],
                ["plain"],
            ],
        )


class TestIterPayloadsFromTable(unittest.TestCase):
    """Tests for bounded Spark-to-pandas batches."""

    def test_yields_header_and_bounded_batches(self):
        spark_client = MagicMock()
        dataframe = MagicMock()
        dataframe.columns = ["id_user", "user_name", "year", "month", "day"]
        selected_dataframe = MagicMock()
        rows = []
        for values in (
            {"id_user": 1, "user_name": "Alice"},
            {"id_user": 2, "user_name": "Bob"},
            {"id_user": 3, "user_name": "Carol"},
        ):
            row = MagicMock()
            row.asDict.return_value = values
            rows.append(row)
        selected_dataframe.toLocalIterator.return_value = iter(rows)
        dataframe.select.return_value = selected_dataframe
        spark_client.get_records.return_value = dataframe

        payloads = list(
            job._iter_payloads_from_table(
                spark_client,
                "employees",
                "2025-03-12",
                chunk_size=2,
            )
        )

        self.assertEqual(payloads[0], ["id_user", "user_name"])
        self.assertEqual(
            payloads[1:],
            [
                [[1, "Alice"], [2, "Bob"]],
                [[3, "Carol"]],
            ],
        )
        dataframe.select.assert_called_once_with(["id_user", "user_name"])
        query = spark_client.get_records.call_args.args[0]
        self.assertIn("reverse_reports.employees", query)
        self.assertIn("year = 2025", query)
        self.assertIn("month = 3", query)
        self.assertIn("day = 12", query)


class TestWritePayloadStreaming(unittest.TestCase):
    """Tests for incremental worksheet writes."""

    def _build_writer(self):
        writer = MagicMock()
        workbook = MagicMock()
        worksheet = MagicMock()
        worksheet.row_count = 1_000
        worksheet.col_count = 26
        writer.google_sheets_client.gsheets.open_by_key.return_value = workbook
        workbook.worksheet.return_value = worksheet
        return writer, worksheet

    def test_writes_each_batch_without_collecting_payload(self):
        writer, worksheet = self._build_writer()
        payload_chunks = iter(
            [
                ["id_user"],
                [[1], [2]],
                [[3]],
            ]
        )

        job._write_payload_streaming(
            writer,
            "Employees",
            "sheet-id",
            payload_chunks,
        )

        worksheet.clear.assert_called_once()
        self.assertEqual(
            worksheet.update.call_args_list,
            [
                call("A1", [["id_user"], [1], [2]], raw=False),
                call("A4", [[3]], raw=False),
            ],
        )

    def test_writes_header_when_table_has_no_rows(self):
        writer, worksheet = self._build_writer()

        job._write_payload_streaming(
            writer,
            "Employees",
            "sheet-id",
            iter([["id_user"]]),
        )

        worksheet.update.assert_called_once_with(
            "A1",
            [["id_user"]],
            raw=False,
        )


class TestMain(unittest.TestCase):
    """Tests for the Spark client configuration used by the entry point."""

    @patch(f"{MODULE_UNDER_TEST}._write_payload_streaming")
    @patch(f"{MODULE_UNDER_TEST}._get_gsheets_writer")
    @patch(f"{MODULE_UNDER_TEST}._iter_payloads_from_table")
    @patch(f"{MODULE_UNDER_TEST}.SparkClient")
    @patch(f"{MODULE_UNDER_TEST}.BaseDBUtils")
    def test_uses_job_name_when_creating_spark_client(
        self,
        mock_base_dbutils,
        mock_spark_client,
        mock_iter_payloads,
        mock_get_writer,
        mock_write_streaming,
    ):
        mock_dbutils = MagicMock()
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils
        mock_iter_payloads.return_value = iter([["id_user"], [[1]]])

        with patch(
            "sys.argv",
            [
                "script",
                "employees",
                "2025-03-12",
                "prod",
                "sheet-id",
                "Employees",
            ],
        ):
            job.main()

        mock_spark_client.assert_called_once_with(app_name=job.JOB_NAME)
        mock_write_streaming.assert_called_once()


if __name__ == "__main__":
    unittest.main()
