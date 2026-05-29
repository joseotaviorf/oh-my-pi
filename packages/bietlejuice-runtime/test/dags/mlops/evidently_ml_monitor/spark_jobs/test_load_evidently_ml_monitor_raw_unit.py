"""Pure-function unit tests (no Spark runtime required)."""

import re
import sys
import unittest
from unittest.mock import MagicMock

mock_pyspark = MagicMock()
sys.modules.setdefault("pyspark", mock_pyspark)
sys.modules.setdefault("pyspark.sql", MagicMock())
sys.modules.setdefault("pyspark.sql.functions", MagicMock())
sys.modules.setdefault("pyspark.sql.types", MagicMock())

for _mod in (
    "bietlejuice.base.db",
    "bietlejuice.base.spark",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders",
    "bietlejuice.loaders.s3_loader",
    "bietlejuice.services.configuration_service",
    "bietlejuice.services.metastore_services",
    "quintoandar_logger",
):
    sys.modules.setdefault(_mod, MagicMock())

from dags.mlops.evidently_ml_monitor.spark_jobs.load_evidently_ml_monitor_raw import (  # noqa: E402
    DT_PATH_PATTERN,
    JOB_NAME_PATH_PATTERN,
    METRIC_NAME_PATH_PATTERN,
    PATH_COLUMNS,
    sanitize_metric_name,
)

SAMPLE_PATH = (
    "s3://quintoml-s3-data-quintoandar-com-br/model-monitoring/my-monitoring-job/"
    "model-id/1/dt=2026-05-27/metric_name=Mean%20Score/file.parquet"
)


class TestPathPatterns(unittest.TestCase):
    def test_extracts_job_name_from_s3_path(self):
        match = re.search(JOB_NAME_PATH_PATTERN, SAMPLE_PATH)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "my-monitoring-job")

    def test_extracts_dt_from_s3_path(self):
        match = re.search(DT_PATH_PATTERN, SAMPLE_PATH)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "2026-05-27")

    def test_extracts_metric_name_from_s3_path(self):
        match = re.search(METRIC_NAME_PATH_PATTERN, SAMPLE_PATH)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "Mean%20Score")


class TestPathColumns(unittest.TestCase):
    def test_includes_expected_path_derived_fields(self):
        self.assertIn("job_name", PATH_COLUMNS)
        self.assertIn("metric_name", PATH_COLUMNS)


class TestSanitizeMetricName(unittest.TestCase):
    def test_decodes_url_encoding_and_normalizes(self):
        raw = "Mean%20Bureaus%20Features%20-%20First%20Week%20vs%20Yesterday"
        self.assertEqual(
            sanitize_metric_name(raw),
            "mean_bureaus_features_-_first_week_vs_yesterday",
        )

    def test_empty_string_returns_empty(self):
        self.assertEqual(sanitize_metric_name(""), "")
