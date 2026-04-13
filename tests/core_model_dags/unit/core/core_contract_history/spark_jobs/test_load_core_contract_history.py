"""
Unit tests for CoreContractHistorySparkJob.

Tests verify that the job correctly transforms CDC transactional data into
the fixed 13-column narrow event-log schema used by contract_history.
"""

from types import SimpleNamespace
from unittest.mock import patch

from dags.core.core_contract_history.spark_jobs.load_core_contract_history import (
    CoreContractHistorySparkJob,
)


EXPECTED_HISTORY_COLUMNS = {
    "id_event",
    "id_contract",
    "sk_core_contract",
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


def _make_args(start="2026-01-01", end="2026-02-01"):
    return SimpleNamespace(
        table_name="contract_history",
        load_start_date=start,
        load_end_date=end,
    )


class TestCoreContractHistorySchema:

    def test_create_core_model_returns_13_column_history_schema(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            # act
            result = job.create_core_model(spark_session, args)

        # assert
        assert len(result.columns) == 13
        assert set(result.columns) == EXPECTED_HISTORY_COLUMNS

    def test_payload_is_null_for_all_cdc_rows(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            # act
            result = job.create_core_model(spark_session, args)

        # assert — CDC source never populates payload (outbox pattern only)
        for row in result.collect():
            assert row["payload"] is None

    def test_event_type_is_cdc_for_all_rows(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            # act
            result = job.create_core_model(spark_session, args)

        # assert
        for row in result.collect():
            assert row["event_type"] == "cdc"

    def test_event_origin_matches_transactional_table_config(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            # act
            result = job.create_core_model(spark_session, args)

        # assert — event_origin must match CONTRACT_TRANSACTIONAL_TABLE from config
        for row in result.collect():
            assert row["event_origin"] == "test.transactional_contrato"


class TestCoreContractHistoryEventDetection:

    def test_create_operation_emits_event_for_all_tracked_columns(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange — transactional_contract_df has one 'c' (create) CDC row
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            # act
            result = job.create_core_model(spark_session, args)

        event_names = {r["event_name"] for r in result.collect()}
        # All event names present from the create row (ev_{target_col})
        assert "ev_status" in event_names
        assert "ev_id_house" in event_names
        assert "ev_id_tenant" in event_names
        assert "ev_paying_condo" in event_names

    def test_update_operation_emits_event_only_for_changed_columns(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange — the fixture has a 'u' row where only status changed
        # (atualizadoEm also changes; other columns stay the same)
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            # act
            result = job.create_core_model(spark_session, args)

        # Only status and atualizadoEm changed between 'c' and 'u' rows
        update_events = [
            r
            for r in result.collect()
            if r["ts_transaction"].year == 2026
            and r["ts_transaction"].month == 1
            and r["ts_transaction"].day == 11
        ]
        update_event_names = {r["event_name"] for r in update_events}
        assert "ev_status" in update_event_names
        assert (
            "ev_id_house" not in update_event_names
        ), "id_house did not change in the update row — should not emit an event"


class TestCoreContractHistoryIdempotency:

    def test_id_event_is_deterministic_hash(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange — run twice, id_event must be identical
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            result1 = job.create_core_model(spark_session, args)
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            result2 = job.create_core_model(spark_session, args)

        ids1 = {r["id_event"] for r in result1.collect()}
        ids2 = {r["id_event"] for r in result2.collect()}
        assert ids1 == ids2, "id_event must be deterministic across runs"

    def test_id_event_is_sha256_hex_string(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["id_event"] is not None
            assert (
                len(row["id_event"]) == 64
            ), f"Expected SHA-256 hex (64 chars), got {len(row['id_event'])}"
