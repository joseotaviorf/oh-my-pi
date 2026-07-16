import re
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.conf"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.types"] = MagicMock()
sys.modules["pyspark.sql.dataframe"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()

sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services"] = MagicMock()
sys.modules["bietlejuice.services.configuration_service"] = MagicMock()
sys.modules["bietlejuice.loaders"] = MagicMock()
sys.modules["bietlejuice.loaders.s3_loader"] = MagicMock()
sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.base.db"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.validation"] = MagicMock()
sys.modules["bietlejuice.base.validation.spark_args"] = MagicMock()

import dags.governance.inmetro.spark_jobs.load_inmetro_raw as load_inmetro_raw  # noqa: E402, I001
from dags.governance.inmetro.spark_jobs.load_inmetro_raw import (  # noqa: E402, I001
    _build_inmetro_glob_path,
    _build_inmetro_path_pattern,
    _generate_date_range,
)


class TestGenerateDateRange(unittest.TestCase):
    def test_single_day_returns_one_date(self):
        result = _generate_date_range("2024-01-01", "2024-01-01")
        self.assertEqual(result, ["2024-01-01"])

    def test_two_consecutive_days(self):
        result = _generate_date_range("2024-01-01", "2024-01-02")
        self.assertEqual(result, ["2024-01-01", "2024-01-02"])

    def test_week_range_returns_seven_dates(self):
        result = _generate_date_range("2024-03-01", "2024-03-07")
        self.assertEqual(len(result), 7)
        self.assertEqual(result[0], "2024-03-01")
        self.assertEqual(result[-1], "2024-03-07")

    def test_month_boundary(self):
        result = _generate_date_range("2024-01-31", "2024-02-01")
        self.assertEqual(result, ["2024-01-31", "2024-02-01"])

    def test_inverted_range_raises_value_error(self):
        with self.assertRaises(ValueError) as ctx:
            _generate_date_range("2024-01-05", "2024-01-01")
        self.assertIn("load_start_date", str(ctx.exception))

    def test_dates_are_formatted_as_yyyy_mm_dd(self):
        result = _generate_date_range("2024-06-09", "2024-06-11")
        for date in result:
            self.assertRegex(date, r"^\d{4}-\d{2}-\d{2}$")


class TestBuildInmetroGlobPath(unittest.TestCase):
    def setUp(self):
        load_inmetro_raw.bucket_directory = "validation"

    def test_glob_has_three_wildcards_for_repo_database_table(self):
        result = _build_inmetro_glob_path("s3://bucket", "2024-06-09")
        self.assertEqual(result, "s3://bucket/*/*/*/validation/2024-06-09")


class TestBuildInmetroPathPattern(unittest.TestCase):
    def setUp(self):
        load_inmetro_raw.bucket_directory = "validation"

    def test_pattern_extracts_repo_database_table_in_order(self):
        pattern = _build_inmetro_path_pattern("s3://bucket", "2024-06-09")
        file_path = "s3://bucket/bietlejuice/hr_system/workers/validation/2024-06-09/result.json"
        match = re.match(pattern, file_path)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "bietlejuice")
        self.assertEqual(match.group(2), "hr_system")
        self.assertEqual(match.group(3), "workers")

    def test_pattern_matches_non_bietlejuice_repo(self):
        pattern = _build_inmetro_path_pattern("s3://bucket", "2024-06-09")
        file_path = (
            "s3://bucket/wonka/some_db/some_table/validation/2024-06-09/result.json"
        )
        match = re.match(pattern, file_path)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "wonka")

    def test_pattern_tolerates_hyphens_and_dots_in_database_or_table(self):
        pattern = _build_inmetro_path_pattern("s3://bucket", "2024-06-09")
        file_path = (
            "s3://bucket/bietlejuice/hr-system.v2/workers-details/"
            "validation/2024-06-09/result.json"
        )
        match = re.match(pattern, file_path)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(2), "hr-system.v2")
        self.assertEqual(match.group(3), "workers-details")


class TestGetInmetroDataErrorBranches(unittest.TestCase):
    def setUp(self):
        load_inmetro_raw.bucket_directory = "validation"
        load_inmetro_raw.source = "test_source"
        self.logger_patcher = patch.object(load_inmetro_raw, "logger", new=MagicMock())
        self.mock_logger = self.logger_patcher.start()
        self.config_patcher = patch.object(load_inmetro_raw, "ConfigurationService")
        mock_config_cls = self.config_patcher.start()
        mock_config_cls.return_value.get_config.return_value = "s3://test-bucket"

    def tearDown(self):
        self.logger_patcher.stop()
        self.config_patcher.stop()

    def test_existence_check_failure_is_recorded_as_errored(self):
        with patch.object(
            load_inmetro_raw, "_path_has_objects", side_effect=Exception("boom")
        ):
            load_inmetro_raw.get_inmetro_data(
                False, ["year"], "2024-06-09", "2024-06-09"
            )

        error_messages = [
            call.args[0] for call in self.mock_logger.error.call_args_list
        ]
        self.assertTrue(
            any("Path existence check failed" in msg for msg in error_messages)
        )
        summary_calls = [
            call.args[0] for call in self.mock_logger.warning.call_args_list
        ]
        self.assertTrue(any("errored=['2024-06-09']" in msg for msg in summary_calls))

    def test_read_failure_after_objects_exist_is_recorded_as_errored(self):
        with (
            patch.object(load_inmetro_raw, "_path_has_objects", return_value=True),
            patch.object(
                load_inmetro_raw,
                "_load_single_date",
                side_effect=Exception("malformed json"),
            ),
        ):
            load_inmetro_raw.get_inmetro_data(
                False, ["year"], "2024-06-09", "2024-06-09"
            )

        error_messages = [
            call.args[0] for call in self.mock_logger.error.call_args_list
        ]
        self.assertTrue(
            any(
                "Read failed although objects exist at path" in msg
                for msg in error_messages
            )
        )
        summary_calls = [
            call.args[0] for call in self.mock_logger.warning.call_args_list
        ]
        self.assertTrue(any("errored=['2024-06-09']" in msg for msg in summary_calls))

    def test_no_objects_at_path_is_skipped_not_errored(self):
        with patch.object(load_inmetro_raw, "_path_has_objects", return_value=False):
            result = load_inmetro_raw.get_inmetro_data(
                False, ["year"], "2024-06-09", "2024-06-09"
            )

        self.assertIsNone(result)
        self.mock_logger.error.assert_not_called()
        summary_calls = [call.args[0] for call in self.mock_logger.info.call_args_list]
        self.assertTrue(
            any("skipped_no_data=['2024-06-09']" in msg for msg in summary_calls)
        )
        self.mock_logger.warning.assert_not_called()
