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
    _generate_date_range,
    _list_inmetro_date_prefixes,
    _parse_inmetro_date_prefix,
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


class TestParseInmetroDatePrefix(unittest.TestCase):
    def setUp(self):
        load_inmetro_raw.bucket_directory = "validation"

    def test_extracts_repo_database_table_in_order(self):
        path = "s3://bucket/bietlejuice/hr_system/workers/validation/2024-06-09"
        self.assertEqual(
            _parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"),
            ("bietlejuice", "hr_system", "workers"),
        )

    def test_tolerates_trailing_slash_and_nested_file(self):
        path = (
            "s3://bucket/bietlejuice/hr_system/workers/validation/"
            "2024-06-09/result.json"
        )
        self.assertEqual(
            _parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"),
            ("bietlejuice", "hr_system", "workers"),
        )

    def test_matches_non_bietlejuice_repo(self):
        path = "s3://bucket/wonka/some_db/some_table/validation/2024-06-09"
        self.assertEqual(
            _parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"),
            ("wonka", "some_db", "some_table"),
        )

    def test_tolerates_hyphens_and_dots_in_database_or_table(self):
        path = (
            "s3://bucket/bietlejuice/hr-system.v2/workers-details/validation/2024-06-09"
        )
        self.assertEqual(
            _parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"),
            ("bietlejuice", "hr-system.v2", "workers-details"),
        )

    def test_rejects_wrong_bucket_directory(self):
        path = "s3://bucket/bietlejuice/hr_system/workers/profile/2024-06-09"
        self.assertIsNone(_parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"))

    def test_rejects_wrong_date(self):
        path = "s3://bucket/bietlejuice/hr_system/workers/validation/2024-06-10"
        self.assertIsNone(_parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"))

    def test_rejects_path_outside_bucket(self):
        path = "s3://other/bietlejuice/hr_system/workers/validation/2024-06-09"
        self.assertIsNone(_parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"))

    def test_accepts_s3a_path_when_bucket_is_s3(self):
        path = "s3a://bucket/bietlejuice/hr_system/workers/validation/2024-06-09"
        self.assertEqual(
            _parse_inmetro_date_prefix(path, "s3://bucket", "2024-06-09"),
            ("bietlejuice", "hr_system", "workers"),
        )

    def test_accepts_s3_path_when_bucket_is_s3a(self):
        path = "s3://bucket/bietlejuice/hr_system/workers/validation/2024-06-09"
        self.assertEqual(
            _parse_inmetro_date_prefix(path, "s3a://bucket", "2024-06-09"),
            ("bietlejuice", "hr_system", "workers"),
        )


class TestListInmetroDatePrefixes(unittest.TestCase):
    def setUp(self):
        load_inmetro_raw.bucket_directory = "validation"

    def _status(self, path):
        status = MagicMock()
        status.getPath.return_value.toString.return_value = path
        return status

    def test_globs_objects_under_date_directory(self):
        with patch.object(
            load_inmetro_raw, "_glob_status", return_value=[]
        ) as mock_glob:
            _list_inmetro_date_prefixes("s3://bucket", "2024-06-09")
        mock_glob.assert_called_once_with("s3://bucket/*/*/*/validation/2024-06-09/*")

    def test_returns_distinct_prefixes_with_reconstructed_paths(self):
        statuses = [
            self._status(
                "s3://bucket/bietlejuice/hr_system/workers/validation/"
                "2024-06-09/result.json"
            ),
            self._status(
                "s3a://bucket/bietlejuice/hr_system/workers/validation/"
                "2024-06-09/other.json"
            ),
            self._status(
                "s3a://bucket/wonka/db_a/tbl_a/validation/2024-06-09/result.json"
            ),
        ]
        with patch.object(load_inmetro_raw, "_glob_status", return_value=statuses):
            result = _list_inmetro_date_prefixes("s3://bucket", "2024-06-09")

        self.assertEqual(
            result,
            [
                (
                    "bietlejuice",
                    "hr_system",
                    "workers",
                    "s3://bucket/bietlejuice/hr_system/workers/validation/2024-06-09",
                ),
                (
                    "wonka",
                    "db_a",
                    "tbl_a",
                    "s3://bucket/wonka/db_a/tbl_a/validation/2024-06-09",
                ),
            ],
        )

    def test_empty_glob_returns_empty_list(self):
        with patch.object(load_inmetro_raw, "_glob_status", return_value=[]):
            self.assertEqual(
                _list_inmetro_date_prefixes("s3://bucket", "2024-06-09"), []
            )


class TestLoadSingleDateUsesLiterals(unittest.TestCase):
    """Hot path must attach repo/database/table via lit(), not name-resolved fns."""

    def setUp(self):
        load_inmetro_raw.bucket_directory = "validation"

    def test_load_single_date_calls_lit_not_regexp_extract(self):
        prefixes = [
            (
                "bietlejuice",
                "hr_system",
                "workers",
                "s3://bucket/bietlejuice/hr_system/workers/validation/2024-06-09",
            )
        ]
        mock_df = MagicMock()
        mock_df.withColumn.return_value = mock_df
        mock_df.select.return_value = mock_df
        mock_df.unionByName.return_value = mock_df
        mock_df.columns = ["col_a"]

        mock_spark_svc = MagicMock()
        mock_spark_svc.input.return_value = mock_spark_svc
        mock_spark_svc.create_year_month_day_columns_from_date.return_value = (
            mock_spark_svc
        )
        mock_spark_svc.optimize_partitions_by_partition_columns.return_value = (
            mock_spark_svc
        )
        mock_spark_svc.output.return_value = mock_df

        with (
            patch.object(
                load_inmetro_raw, "_list_inmetro_date_prefixes", return_value=prefixes
            ),
            patch.object(load_inmetro_raw.spark, "read") as mock_read,
            patch.object(load_inmetro_raw, "lit") as mock_lit,
            patch.object(
                load_inmetro_raw, "SparkDataFrameService", return_value=mock_spark_svc
            ),
        ):
            mock_read.format.return_value.load.return_value = mock_df
            mock_lit.side_effect = lambda value: f"lit({value})"

            load_inmetro_raw._load_single_date(
                "2024-06-09", False, ["year", "month", "day"], "s3://bucket"
            )

        mock_read.format.return_value.load.assert_called_once_with(prefixes[0][3])
        mock_lit.assert_any_call("bietlejuice")
        mock_lit.assert_any_call("hr_system")
        mock_lit.assert_any_call("workers")
        self.assertEqual(mock_lit.call_count, 3)

    def test_load_single_date_unions_prefixes_with_allow_missing_columns(self):
        prefixes = [
            (
                "bietlejuice",
                "db_a",
                "tbl_a",
                "s3://bucket/bietlejuice/db_a/tbl_a/validation/2024-06-09",
            ),
            (
                "wonka",
                "db_b",
                "tbl_b",
                "s3://bucket/wonka/db_b/tbl_b/validation/2024-06-09",
            ),
        ]
        df_a = MagicMock(name="df_a")
        df_b = MagicMock(name="df_b")
        df_a.withColumn.return_value = df_a
        df_b.withColumn.return_value = df_b
        df_union = MagicMock(name="df_union")
        df_a.unionByName.return_value = df_union

        mock_spark_svc = MagicMock()
        mock_spark_svc.input.return_value = mock_spark_svc
        mock_spark_svc.create_year_month_day_columns_from_date.return_value = (
            mock_spark_svc
        )
        mock_spark_svc.optimize_partitions_by_partition_columns.return_value = (
            mock_spark_svc
        )
        mock_spark_svc.output.return_value = df_union

        with (
            patch.object(
                load_inmetro_raw, "_list_inmetro_date_prefixes", return_value=prefixes
            ),
            patch.object(load_inmetro_raw.spark, "read") as mock_read,
            patch.object(load_inmetro_raw, "lit", side_effect=lambda v: v),
            patch.object(
                load_inmetro_raw, "SparkDataFrameService", return_value=mock_spark_svc
            ),
        ):
            mock_read.format.return_value.load.side_effect = [df_a, df_b]
            load_inmetro_raw._load_single_date(
                "2024-06-09", False, ["year", "month", "day"], "s3://bucket"
            )

        df_a.unionByName.assert_called_once_with(df_b, allowMissingColumns=True)

    def test_load_single_date_raises_when_no_prefixes(self):
        with patch.object(
            load_inmetro_raw, "_list_inmetro_date_prefixes", return_value=[]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                load_inmetro_raw._load_single_date(
                    "2024-06-09", False, ["year"], "s3://bucket"
                )
        self.assertIn("No parseable producer prefixes", str(ctx.exception))


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
