"""Unit tests for ``GenericContractQualityChecks`` (Spark calls mocked)."""

import sys
from unittest.mock import MagicMock, patch

import pytest

if "bietlejuice.base.sst.core.utils.common" not in sys.modules:
    _stub_common = MagicMock()
    _stub_common.validate_and_write = MagicMock()
    sys.modules["bietlejuice.base.sst.core.utils.common"] = _stub_common

from bietlejuice.base.sst.pipelines.quality.contracts.generic import (
    GenericContractQualityChecks,
)

TABLE = "datalake_salesforce_clean.events_case"
BUCKET = "test-bucket"


@pytest.fixture
def mock_pyspark_functions():
    """Patch ``F.col`` / ``F.lit`` / ``F.max`` so tests do not need a Spark JVM."""
    with patch("bietlejuice.base.sst.pipelines.quality.contracts.generic.F") as mock_f:
        col = MagicMock()
        mock_f.col.return_value = col
        col.__ge__ = MagicMock(return_value=MagicMock())
        mock_f.lit.return_value = MagicMock()
        mock_f.max.return_value = MagicMock()
        yield mock_f


@pytest.fixture
def spark_table_chain():
    """
    Build ``spark.table(name).where(...)->df`` with configurable ``count()`` and
    ``select(...).collect()`` for the success path.
    """

    def _factory(*, count: int, last_ts: str = "2026-04-07 15:00:00"):
        spark = MagicMock()
        df = MagicMock()
        df.count.return_value = count
        select_result = MagicMock()
        select_result.collect.return_value = [[last_ts]]
        df.select.return_value = select_result
        spark.table.return_value.where.return_value = df
        return spark, df

    return _factory


def _make_checks(spark, **kwargs):
    return GenericContractQualityChecks(
        spark=spark, table_name=TABLE, bucket=BUCKET, **kwargs
    )


class TestCheckEmptyPartitions:
    """Behaviour of ``_freshness_check``."""

    @pytest.mark.parametrize("threshold_hours", [1, 24, 72])
    def test_logs_warning_when_filtered_frame_is_empty(
        self, mock_pyspark_functions, spark_table_chain, threshold_hours
    ):
        spark, _ = spark_table_chain(count=0)
        checks = _make_checks(spark, threshold_time_hours=threshold_hours)

        with patch.object(checks.logger, "warning") as mock_warning:
            checks._freshness_check()

        mock_warning.assert_called_once()
        msg = mock_warning.call_args[0][0]
        assert TABLE in msg
        assert str(threshold_hours) in msg
        assert "has no data in the last" in msg

    def test_appends_failed_metric_when_count_is_zero(
        self, mock_pyspark_functions, spark_table_chain
    ):
        spark, _ = spark_table_chain(count=0)
        checks = _make_checks(spark)

        checks._freshness_check()

        assert len(checks.quality_checks_data) == 1
        row = checks.quality_checks_data[0]
        assert row["status"] == "failed"
        assert row["metric_name"] == "freshness"
        assert row["table_name"] == TABLE
        assert row["layer"] == "clean"
        assert row["count_rows"] == 0

    def test_appends_success_metric_when_rows_exist(
        self, mock_pyspark_functions, spark_table_chain
    ):
        spark, _ = spark_table_chain(count=3, last_ts="2026-04-07 12:34:56")
        checks = _make_checks(spark)

        checks._freshness_check()

        assert len(checks.quality_checks_data) == 1
        row = checks.quality_checks_data[0]
        assert row["status"] == "success"
        assert row["metric_name"] == "freshness"
        assert row["table_name"] == TABLE
        assert row["layer"] == "clean"
        assert row["count_rows"] == 3
        assert row["last_row_timestamp"] == "2026-04-07 12:34:56"

    def test_reads_qualified_table_name(
        self, mock_pyspark_functions, spark_table_chain
    ):
        spark, _ = spark_table_chain(count=1)
        checks = _make_checks(spark)

        checks._freshness_check()

        spark.table.assert_called_once_with(TABLE)

    def test_logs_success_with_last_ts_when_rows_exist(
        self, mock_pyspark_functions, spark_table_chain
    ):
        spark, df = spark_table_chain(count=3, last_ts="2026-04-07 12:34:56")
        checks = _make_checks(spark, threshold_time_hours=24)

        with patch.object(checks.logger, "info") as mock_info:
            checks._freshness_check()

        mock_info.assert_called()
        logged = mock_info.call_args[0][0]
        assert "generic_contract_quality_checks" in logged
        assert TABLE in logged
        assert "is not empty in the last 24 hours" in logged
        assert "2026-04-07 12:34:56" in logged

        df.select.assert_called_once()
        mock_pyspark_functions.max.assert_called_once()


class TestRun:
    """Behaviour of ``run``."""

    @patch(
        "bietlejuice.base.sst.pipelines.quality.contracts.generic.validate_and_write"
    )
    def test_run_logs_start_and_calls_empty_partition_check(
        self, mock_validate_and_write, mock_pyspark_functions, spark_table_chain
    ):
        spark, _ = spark_table_chain(count=1)
        checks = _make_checks(spark)

        with patch.object(checks, "_freshness_check") as mock_check:
            with patch.object(checks.logger, "info") as mock_info:
                checks.run()

        mock_info.assert_called_once()
        assert TABLE in mock_info.call_args[0][0]
        assert "Starting generic contract checks" in mock_info.call_args[0][0]
        mock_check.assert_called_once()
        spark.createDataFrame.assert_called_once()
        mock_validate_and_write.assert_called_once()

    @patch(
        "bietlejuice.base.sst.pipelines.quality.contracts.generic.validate_and_write"
    )
    def test_run_creates_dataframe_and_calls_validate_and_write(
        self, mock_validate_and_write, mock_pyspark_functions, spark_table_chain
    ):
        spark, _ = spark_table_chain(count=1, last_ts="2026-04-08 10:00:00")
        checks = _make_checks(spark)

        with patch.object(checks.logger, "info"):
            checks.run()

        spark.createDataFrame.assert_called_once()
        call_args = spark.createDataFrame.call_args
        assert call_args[0][0] == checks.quality_checks_data
        assert call_args[0][1] is checks.quality_checks_schema

        mock_validate_and_write.assert_called_once_with(
            spark=spark,
            df=spark.createDataFrame.return_value,
            target_table=checks.quality_checks_table,
            table_location=f"s3a://{BUCKET}/sst_metrics/contract_quality_checks",
            partition_cols=["metric_name", "table_name"],
            overwrite_schema=True,
            append=True,
            sync_hive=True,
        )

    @patch(
        "bietlejuice.base.sst.pipelines.quality.contracts.generic.validate_and_write"
    )
    def test_run_persists_failed_metric_when_table_empty(
        self, mock_validate_and_write, mock_pyspark_functions, spark_table_chain
    ):
        spark, _ = spark_table_chain(count=0)
        checks = _make_checks(spark)

        with patch.object(checks.logger, "info"):
            with patch.object(checks.logger, "warning"):
                with pytest.raises(ValueError, match="Failed contract checks"):
                    checks.run()

        spark.createDataFrame.assert_called_once()
        mock_validate_and_write.assert_called_once()
        rows = spark.createDataFrame.call_args[0][0]
        assert len(rows) == 1
        assert rows[0]["status"] == "failed"
        assert rows[0]["count_rows"] == 0
        assert rows[0]["metric_name"] == "freshness"
