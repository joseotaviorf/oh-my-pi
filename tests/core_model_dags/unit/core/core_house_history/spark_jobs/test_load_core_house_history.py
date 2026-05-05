"""
Unit tests for CoreHouseHistorySparkJob.

Tests verify that the job correctly transforms CDC transactional data into
the fixed 13-column narrow event-log schema used by house_history, including
the complex id_owner / uuid_owner resolution from combined house + HLR + user
timelines with as-of joins.
"""

from types import SimpleNamespace
from unittest.mock import patch, MagicMock

from pyspark.sql.utils import AnalysisException

from dags.core.core_house_history.spark_jobs.load_core_house_history import (
    CoreHouseHistorySparkJob,
)


EXPECTED_HISTORY_COLUMNS = {
    "id_event",
    "id_house",
    "sk_core_house",
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

_MODULE = (
    "dags.core.core_house_history.spark_jobs.load_core_house_history"
)

_HLR_VIEW = "test_hlr"
_USER_VIEW = "test_usuario"


def _make_args(start="2026-01-01", end="2026-02-01"):
    return SimpleNamespace(
        table_name="house_history",
        load_start_date=start,
        load_end_date=end,
    )


def _register_tables(spark_session, hlr_df, usuario_df):
    """Register fixture DataFrames as temp views so spark.read.table() works."""
    hlr_df.createOrReplaceTempView(_HLR_VIEW)
    usuario_df.createOrReplaceTempView(_USER_VIEW)


def _run_create_core_model(spark_session, imovel_df, hlr_df, usuario_df, mock_cfg, args=None):
    """Helper that registers tables and runs create_core_model."""
    if args is None:
        args = _make_args()

    _register_tables(spark_session, hlr_df, usuario_df)

    job = CoreHouseHistorySparkJob()

    with patch(
        f"{_MODULE}.HistoricalHelper.load_transactional_data",
        return_value=imovel_df,
    ):
        return job.create_core_model(spark_session, args)


class TestCoreHouseHistorySchema:

    def test_create_core_model_returns_13_column_history_schema(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        assert len(result.columns) == 13
        assert set(result.columns) == EXPECTED_HISTORY_COLUMNS

    def test_payload_is_null_for_all_cdc_rows(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        for row in result.collect():
            assert row["payload"] is None

    def test_event_type_is_cdc_for_all_rows(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        for row in result.collect():
            assert row["event_type"] == "cdc"


class TestCoreHouseHistoryFieldEvents:

    def test_create_operation_emits_events_for_tracked_columns(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        event_names = {r["event_name"] for r in result.collect()}
        expected_field_events = {
            "ev_id_external", "ev_id_region", "ev_id_user_registrant",
            "ev_address", "ev_number", "ev_neighborhood", "ev_complement",
            "ev_zipcode", "ev_city", "ev_type", "ev_total_area",
            "ev_lat", "ev_lng", "ev_total_bathrooms", "ev_total_bedrooms",
            "ev_total_suites", "ev_floor", "ev_ts_created", "ev_ts_updated",
        }
        expected_owner_events = {"ev_id_owner", "ev_uuid_owner"}
        missing = (expected_field_events | expected_owner_events) - event_names
        assert not missing, f"Missing event names: {missing}"

    def test_update_emits_only_changed_columns(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        update_events = [
            r for r in result.collect()
            if r["ts_transaction"].day == 15 and r["ts_transaction"].month == 1
        ]
        update_event_names = {r["event_name"] for r in update_events}
        assert "ev_ts_updated" in update_event_names, "atualizadoEm changed"
        assert "ev_address" not in update_event_names, "address did not change"

    def test_registrant_coalesce_uses_original_when_present(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        registrant_events = [
            r for r in result.collect()
            if r["event_name"] == "ev_id_user_registrant"
        ]
        assert len(registrant_events) > 0
        assert registrant_events[0]["value"] == "50"

    def test_field_event_origin_is_house_transactional_table(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        field_events = [
            r for r in result.collect()
            if r["event_name"] not in ("ev_id_owner", "ev_uuid_owner")
        ]
        for row in field_events:
            assert row["event_origin"] == "test_transactional_imovel"


class TestCoreHouseHistoryOwnerEvents:

    def test_owner_events_are_emitted(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        event_names = {r["event_name"] for r in result.collect()}
        assert "ev_id_owner" in event_names
        assert "ev_uuid_owner" in event_names

    def test_owner_fallback_to_usuario_id_when_no_hlr(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_empty_df,  # HLR has zero records
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_empty_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        owner_events = [
            r for r in result.collect()
            if r["event_name"] == "ev_id_owner"
        ]
        owner_values = {r["value"] for r in owner_events}
        assert "100" in owner_values or "150" in owner_values, \
            "Without HLR, id_owner should fallback to usuario_id"

    def test_owner_from_hlr_when_user_exists(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        owner_events = [
            r for r in result.collect()
            if r["event_name"] == "ev_id_owner"
        ]
        owner_values = {r["value"] for r in owner_events}
        assert "200" in owner_values, \
            "HLR relatedId=200 exists as usuario, should become id_owner"

    def test_uuid_owner_resolved_from_usuario(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        uuid_events = [
            r for r in result.collect()
            if r["event_name"] == "ev_uuid_owner"
        ]
        uuid_values = {r["value"] for r in uuid_events}
        assert "uuid-ccc" in uuid_values, \
            "uuid_owner for id_owner=200 should be uuid-ccc"

    def test_hlr_delete_causes_fallback_to_usuario_id(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_with_delete_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_with_delete_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        owner_events = sorted(
            [r for r in result.collect() if r["event_name"] == "ev_id_owner"],
            key=lambda r: r["ts_transaction"],
        )
        values_over_time = [r["value"] for r in owner_events]
        assert "200" in values_over_time, "HLR create should set owner to 200"
        last_non_200 = [v for v in values_over_time if v != "200"]
        assert len(last_non_200) > 0, \
            "After HLR delete, owner should revert to fallback (usuario_id)"

    def test_id_owner_event_origin_reflects_source(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        owner_events = [
            r for r in result.collect()
            if r["event_name"] == "ev_id_owner"
        ]
        origins = {r["event_origin"] for r in owner_events}
        valid_origins = {
            "test_transactional_imovel",
            "test_hlr",
        }
        assert origins.issubset(valid_origins), \
            f"id_owner event_origin must be house or HLR table, got {origins}"

    def test_uuid_owner_event_origin_is_usuario_table(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        uuid_events = [
            r for r in result.collect()
            if r["event_name"] == "ev_uuid_owner"
        ]
        for row in uuid_events:
            assert row["event_origin"] == "test_usuario"


class TestCoreHouseHistoryAsOfJoin:

    def test_hlr_owner_not_resolved_when_user_created_after_event(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_late_df,
        mock_configuration_service,
    ):
        """User 200 created on Feb 1, HLR points to 200 on Jan 12.
        As-of join should NOT validate user 200 for events before Feb 1,
        so id_owner should fallback to usuario_id."""
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_late_df,
            mock_configuration_service,
        )

        owner_events = [
            r for r in result.collect()
            if r["event_name"] == "ev_id_owner"
        ]
        owner_values = {r["value"] for r in owner_events}
        assert "200" not in owner_values, \
            "User 200 did not exist during the events — should not appear as id_owner"


class TestCoreHouseHistoryIdempotency:

    def test_id_event_is_deterministic_hash(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result1 = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )
        result2 = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        ids1 = {r["id_event"] for r in result1.collect()}
        ids2 = {r["id_event"] for r in result2.collect()}
        assert ids1 == ids2, "id_event must be deterministic across runs"

    def test_id_event_is_sha256_hex_string(
        self,
        spark_session,
        transactional_imovel_df,
        transactional_hlr_df,
        transactional_usuario_df,
        mock_configuration_service,
    ):
        result = _run_create_core_model(
            spark_session,
            transactional_imovel_df,
            transactional_hlr_df,
            transactional_usuario_df,
            mock_configuration_service,
        )

        for row in result.collect():
            assert row["id_event"] is not None
            assert len(row["id_event"]) == 64, \
                f"Expected SHA-256 hex (64 chars), got {len(row['id_event'])}"


class TestMergeStrategyConfig:

    def test_merge_on_historical_uses_natural_key_with_partition_columns(
        self, mock_configuration_service
    ):
        job = CoreHouseHistorySparkJob()
        merge_on = job.get_config("merge_on_historical", required=True)

        assert merge_on == [
            "id_house", "event_name", "ts_transaction",
            "year", "month", "day",
        ]

    def test_when_matched_update_condition_is_false(
        self, mock_configuration_service
    ):
        job = CoreHouseHistorySparkJob()
        condition = job.get_config(
            "when_matched_update_condition_historical",
            required=False,
            default=None,
        )

        assert condition == "FALSE"


class TestTargetTableEmptyDetection:

    def test_returns_true_when_table_does_not_exist(self, spark_session):
        job = CoreHouseHistorySparkJob()

        result = job._is_target_table_empty(
            spark_session, "nonexistent_db.nonexistent_table"
        )

        assert result is True

    def test_returns_true_on_analysis_exception(self, spark_session):
        job = CoreHouseHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.side_effect = AnalysisException(
            desc="Table not found",
            stackTrace="",
        )

        result = job._is_target_table_empty(mock_spark, "bad_db.bad_table")

        assert result is True

    def test_returns_true_when_table_is_empty(self):
        job = CoreHouseHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = True

        result = job._is_target_table_empty(mock_spark, "db.empty_table")

        assert result is True

    def test_returns_false_when_table_has_data(self):
        job = CoreHouseHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = False

        result = job._is_target_table_empty(mock_spark, "db.populated_table")

        assert result is False


class TestRunPipelineBypass:

    def _make_pipeline_args(self):
        return SimpleNamespace(
            table_name="house_history",
            load_start_date="2026-01-01",
            load_end_date="2026-02-01",
            partitions="['year', 'month', 'day']",
            schema="core_house",
            bucket="test-bucket",
        )

    @patch(f"{_MODULE}.DataFrameDeltaTableLoaderPipeline")
    def test_uses_direct_write_when_target_is_empty(
        self,
        mock_pipeline_cls,
        spark_session,
        transactional_imovel_df,
        mock_configuration_service,
    ):
        job = CoreHouseHistorySparkJob()
        args = self._make_pipeline_args()

        with patch.object(
            job, "_is_target_table_empty", return_value=True
        ), patch.object(job, "setup_table_privileges", return_value=None):
            job.run_pipeline(transactional_imovel_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] is None
        assert call_kwargs["when_matched_update_condition"] is None

    @patch(f"{_MODULE}.DataFrameDeltaTableLoaderPipeline")
    def test_uses_partition_scoped_merge_when_target_has_data(
        self,
        mock_pipeline_cls,
        spark_session,
        transactional_imovel_df,
        mock_configuration_service,
    ):
        job = CoreHouseHistorySparkJob()
        args = self._make_pipeline_args()

        with patch.object(
            job, "_is_target_table_empty", return_value=False
        ), patch.object(job, "setup_table_privileges", return_value=None):
            job.run_pipeline(transactional_imovel_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] == [
            "id_house", "event_name", "ts_transaction",
            "year", "month", "day",
        ]
        assert call_kwargs["when_matched_update_condition"] == "FALSE"
