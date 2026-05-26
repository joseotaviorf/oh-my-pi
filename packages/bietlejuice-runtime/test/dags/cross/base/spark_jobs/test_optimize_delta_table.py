"""Unit tests for build_year_month_day_predicate in optimize_delta_table."""

import sys
from unittest.mock import MagicMock

import pytest

sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.session"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.context"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.base_spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.runtime_detector"] = MagicMock()
sys.modules["bietlejuice.base.spark.spark_session_factory"] = MagicMock()
sys.modules["bietlejuice.base.db.metastore_mapping_factory"] = MagicMock()
sys.modules["bietlejuice.loaders.delta_loader"] = MagicMock()

from dags.cross.base.spark_jobs.optimize_delta_table import (  # noqa: E402
    _resolve_partition_predicate,
    build_year_month_day_predicate,
)


class TestBuildYearMonthDayPredicate:
    def test_single_day_returns_plain_equality(self):
        predicate = build_year_month_day_predicate("2026-05-26", "2026-05-26")
        assert predicate == "year = 2026 AND month = 5 AND day = 26"

    def test_two_day_window_joins_with_or(self):
        predicate = build_year_month_day_predicate("2026-05-25", "2026-05-26")
        assert predicate == (
            "(year = 2026 AND month = 5 AND day = 25) OR "
            "(year = 2026 AND month = 5 AND day = 26)"
        )

    def test_crosses_month_boundary(self):
        predicate = build_year_month_day_predicate("2026-04-30", "2026-05-01")
        assert predicate == (
            "(year = 2026 AND month = 4 AND day = 30) OR "
            "(year = 2026 AND month = 5 AND day = 1)"
        )

    def test_end_before_start_raises(self):
        with pytest.raises(ValueError, match="must be on or after"):
            build_year_month_day_predicate("2026-05-26", "2026-05-25")

    def test_invalid_date_format_raises(self):
        with pytest.raises(ValueError, match="YYYY-MM-DD"):
            build_year_month_day_predicate("2026/05/26", "2026-05-26")


class TestResolvePartitionPredicate:
    def test_returns_none_when_start_missing(self):
        assert _resolve_partition_predicate(None, "2026-05-26") is None

    def test_returns_none_when_end_missing(self):
        assert _resolve_partition_predicate("2026-05-26", None) is None

    def test_returns_none_when_both_missing(self):
        assert _resolve_partition_predicate(None, None) is None

    def test_returns_predicate_when_both_present(self):
        assert (
            _resolve_partition_predicate("2026-05-26", "2026-05-26")
            == "year = 2026 AND month = 5 AND day = 26"
        )
