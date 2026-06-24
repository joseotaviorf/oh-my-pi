"""
Unit tests for CoreRegionHistorySparkJob.

Covers both output tables:
  - business_unit_region_history (15 cols, junction id entity key)
  - business_unit_history        (13 cols, simple id PK)
"""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from pyspark.sql.utils import AnalysisException

from dags.core.core_region_history.spark_jobs.load_core_region_history import (
    CoreRegionHistorySparkJob,
)

_MODULE = "dags.core.core_region_history.spark_jobs.load_core_region_history"

EXPECTED_BUR_COLUMNS = {
    "id_event",
    "id_business_unit_region",
    "sk_core_business_unit_region",
    "id_region",
    "id_business_unit",
    "event_name",
    "event_type",
    "value",
    "payload",
    "ts_transaction",
    "event_origin",
    "ts_load",
    "year",
    "month",
    "day",
}

EXPECTED_BU_COLUMNS = {
    "id_event",
    "id_business_unit",
    "sk_core_business_unit",
    "event_name",
    "event_type",
    "value",
    "payload",
    "ts_transaction",
    "event_origin",
    "ts_load",
    "year",
    "month",
    "day",
}


def _make_args(table_name, start="2024-01-01", end="2025-01-01"):
    return SimpleNamespace(
        table_name=table_name,
        load_start_date=start,
        load_end_date=end,
    )


# ---------------------------------------------------------------------------
# business_unit_region_history — schema
# ---------------------------------------------------------------------------


class TestBURHistorySchema:
    def test_returns_15_columns(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        assert len(result.columns) == 15

    def test_column_names_match_expected_schema(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        assert set(result.columns) == EXPECTED_BUR_COLUMNS


# ---------------------------------------------------------------------------
# business_unit_region_history — junction key
# ---------------------------------------------------------------------------


class TestBURHistoryJunctionKey:
    def test_junction_id_is_transactional_id(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        rows = result.collect()
        for row in rows:
            assert row["id_business_unit_region"] == "100"
            assert row["id_region"] == "10"
            assert row["id_business_unit"] == "20"

    def test_id_event_is_deterministic(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            r1 = job.create_core_model(spark_session, args)
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            r2 = job.create_core_model(spark_session, args)

        assert {x["id_event"] for x in r1.collect()} == {
            x["id_event"] for x in r2.collect()
        }

    def test_id_event_is_sha256_hex_string(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["id_event"] is not None
            assert len(row["id_event"]) == 64, (
                f"Expected SHA-256 hex (64 chars), got {len(row['id_event'])}"
            )


# ---------------------------------------------------------------------------
# business_unit_region_history — events
# ---------------------------------------------------------------------------


class TestBURHistoryEvents:
    def test_insert_emits_ev_business_context(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        event_names = {r["event_name"] for r in result.collect()}
        assert "ev_business_context" in event_names

    def test_created_at_emits_single_ev_ts_created_per_junction(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        """created_at is immutable, so exactly one ev_ts_created per junction id."""
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        ts_created_rows = [
            r for r in result.collect() if r["event_name"] == "ev_ts_created"
        ]
        assert len(ts_created_rows) == 1
        assert ts_created_rows[0]["value"] == "2024-03-01 08:00:00"

    def test_update_emits_ev_business_context_on_change(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"].day == 5 and r["ts_transaction"].month == 3
        ]
        assert len(update_rows) == 1
        assert update_rows[0]["event_name"] == "ev_business_context"
        assert update_rows[0]["value"] == "RENT"

    def test_event_type_is_cdc_for_all_rows(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["event_type"] == "cdc"

    def test_payload_is_null_for_all_rows(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["payload"] is None

    def test_event_origin_matches_config_table(
        self,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["event_origin"] == "test.business_unit_region"


# ---------------------------------------------------------------------------
# business_unit_region_history — _filter_value_filled
# ---------------------------------------------------------------------------


class TestBURHistoryFilterValues:
    def test_rows_with_null_business_context_are_dropped(
        self,
        spark_session,
        transactional_bur_null_context_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_null_context_df,
        ):
            result = job.create_core_model(spark_session, args)

        event_names = [r["event_name"] for r in result.collect()]
        # The null business_context row is dropped by _filter_value_filled, but the
        # immutable created_at still emits a non-null ev_ts_created on insert.
        assert "ev_business_context" not in event_names, (
            "Rows with null business_context should be filtered out by _filter_value_filled"
        )
        assert event_names == ["ev_ts_created"]


# ---------------------------------------------------------------------------
# business_unit_region_history — re-association
# ---------------------------------------------------------------------------


class TestBURHistoryReassociation:
    def test_same_pair_different_junction_ids_emit_separate_ev_ts_created(
        self,
        spark_session,
        transactional_bur_reassociation_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_reassociation_df,
        ):
            result = job.create_core_model(spark_session, args)

        ts_created_rows = [
            r for r in result.collect() if r["event_name"] == "ev_ts_created"
        ]
        assert len(ts_created_rows) == 2
        junction_ids = {r["id_business_unit_region"] for r in ts_created_rows}
        assert junction_ids == {"100", "101"}
        for row in ts_created_rows:
            assert row["id_region"] == "10"
            assert row["id_business_unit"] == "20"


# ---------------------------------------------------------------------------
# business_unit_region_history — sentinel filter
# ---------------------------------------------------------------------------


class TestBURHistorySentinelFilter:
    def test_zero_key_junction_rows_are_excluded(
        self,
        spark_session,
        transactional_bur_with_zero_key_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_with_zero_key_df,
        ):
            result = job.create_core_model(spark_session, args)

        junction_ids = {r["id_business_unit_region"] for r in result.collect()}
        assert junction_ids == {"100"}


# ---------------------------------------------------------------------------
# business_unit_region_history — FK lookup canonicalization
# ---------------------------------------------------------------------------


class TestBURHistoryFkCanonicalization:
    def test_conflicting_fk_at_same_ts_does_not_duplicate_id_event(
        self,
        spark_session,
        transactional_bur_snapshot_duplicate_fk_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_region_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bur_snapshot_duplicate_fk_df,
        ):
            result = job.create_core_model(spark_session, args)

        rows = result.collect()
        id_events = [r["id_event"] for r in rows]

        assert len(rows) == len(set(id_events)), (
            "FK join must not duplicate history rows at the same (junction, ts)"
        )
        assert len(rows) == 2
        assert {r["event_name"] for r in rows} == {
            "ev_business_context",
            "ev_ts_created",
        }
        for row in rows:
            assert row["id_region"] == "10"
            assert row["id_business_unit"] == "20"


# ---------------------------------------------------------------------------
# business_unit_history — schema
# ---------------------------------------------------------------------------


class TestBUHistorySchema:
    def test_returns_13_columns(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            result = job.create_core_model(spark_session, args)

        assert len(result.columns) == 13

    def test_column_names_match_expected_schema(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            result = job.create_core_model(spark_session, args)

        assert set(result.columns) == EXPECTED_BU_COLUMNS


# ---------------------------------------------------------------------------
# business_unit_history — events
# ---------------------------------------------------------------------------


class TestBUHistoryEvents:
    def test_insert_emits_all_tracked_columns(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            result = job.create_core_model(spark_session, args)

        insert_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"].day == 1 and r["ts_transaction"].month == 3
        ]
        insert_event_names = {r["event_name"] for r in insert_rows}
        expected = {
            "ev_hub_name",
            "ev_sdr_type",
            "ev_lead_types",
            "ev_negotiation_type",
            "ev_operational_context",
            "ev_business_context",
            "ev_ts_created",
        }
        assert expected.issubset(insert_event_names), (
            f"INSERT should emit all tracked columns. Missing: {expected - insert_event_names}"
        )

    def test_created_at_emits_single_ev_ts_created(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        """created_at is immutable, so exactly one ev_ts_created per hub."""
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            result = job.create_core_model(spark_session, args)

        ts_created_rows = [
            r for r in result.collect() if r["event_name"] == "ev_ts_created"
        ]
        assert len(ts_created_rows) == 1
        assert ts_created_rows[0]["value"] == "2024-03-01 08:00:00"

    def test_update_emits_only_changed_column(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        """Only hub_name changes on the second CDC row — only ev_hub_name should fire."""
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            result = job.create_core_model(spark_session, args)

        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"].day == 10 and r["ts_transaction"].month == 3
        ]
        update_event_names = {r["event_name"] for r in update_rows}
        assert "ev_hub_name" in update_event_names
        assert "ev_sdr_type" not in update_event_names
        assert "ev_business_context" not in update_event_names
        # created_at is immutable, so no ev_ts_created event on update
        assert "ev_ts_created" not in update_event_names

    def test_event_type_is_cdc_for_all_rows(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["event_type"] == "cdc"

    def test_payload_is_null_for_all_rows(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["payload"] is None

    def test_id_event_is_deterministic(
        self,
        spark_session,
        transactional_bu_df,
        mock_configuration_bu,
    ):
        job = CoreRegionHistorySparkJob()
        args = _make_args("business_unit_history")

        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            r1 = job.create_core_model(spark_session, args)
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            return_value=transactional_bu_df,
        ):
            r2 = job.create_core_model(spark_session, args)

        assert {x["id_event"] for x in r1.collect()} == {
            x["id_event"] for x in r2.collect()
        }


# ---------------------------------------------------------------------------
# Unsupported table guard
# ---------------------------------------------------------------------------


class TestUnsupportedTable:
    def test_raises_value_error_for_unknown_table_name(self, spark_session):
        job = CoreRegionHistorySparkJob()
        args = _make_args("nonexistent_table")

        with pytest.raises(ValueError, match="Unsupported table_name"):
            with patch(
                f"{_MODULE}.HistoricalHelper.load_transactional_data",
                return_value=MagicMock(),
            ):
                job.create_core_model(spark_session, args)


# ---------------------------------------------------------------------------
# _is_target_table_empty
# ---------------------------------------------------------------------------


class TestTargetTableEmptyDetection:
    def test_returns_true_when_table_does_not_exist(self, spark_session):
        job = CoreRegionHistorySparkJob()

        result = job._is_target_table_empty(
            spark_session, "nonexistent_db.nonexistent_table"
        )

        assert result is True

    def test_returns_true_on_analysis_exception(self, spark_session):
        job = CoreRegionHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.side_effect = AnalysisException(
            "Table not found",
        )

        result = job._is_target_table_empty(mock_spark, "bad_db.bad_table")

        assert result is True

    def test_returns_true_when_table_is_empty(self):
        job = CoreRegionHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = True

        result = job._is_target_table_empty(mock_spark, "db.empty_table")

        assert result is True

    def test_returns_false_when_table_has_data(self):
        job = CoreRegionHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = False

        result = job._is_target_table_empty(mock_spark, "db.populated_table")

        assert result is False


# ---------------------------------------------------------------------------
# run_pipeline — empty-table bypass
# ---------------------------------------------------------------------------


class TestRunPipelineBypass:
    def _make_pipeline_args(self, table_name="business_unit_region_history"):
        return SimpleNamespace(
            table_name=table_name,
            load_start_date="2024-01-01",
            load_end_date="2025-01-01",
            partitions="['year', 'month', 'day']",
            schema="core_region",
            bucket="test-bucket",
        )

    @patch(f"{_MODULE}.DataFrameDeltaTableLoaderPipeline")
    def test_uses_direct_write_when_target_is_empty(
        self,
        mock_pipeline_cls,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = self._make_pipeline_args()

        with (
            patch.object(job, "_is_target_table_empty", return_value=True),
            patch.object(job, "setup_table_privileges", return_value=None),
        ):
            job.run_pipeline(transactional_bur_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] is None
        assert call_kwargs["when_matched_update_condition"] is None

    @patch(f"{_MODULE}.DataFrameDeltaTableLoaderPipeline")
    def test_uses_id_event_merge_when_target_has_data(
        self,
        mock_pipeline_cls,
        spark_session,
        transactional_bur_df,
        mock_configuration_bur,
    ):
        job = CoreRegionHistorySparkJob()
        args = self._make_pipeline_args()

        with (
            patch.object(job, "_is_target_table_empty", return_value=False),
            patch.object(job, "setup_table_privileges", return_value=None),
        ):
            job.run_pipeline(transactional_bur_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] == ["id_event"]
        assert call_kwargs["when_matched_update_condition"] is None
