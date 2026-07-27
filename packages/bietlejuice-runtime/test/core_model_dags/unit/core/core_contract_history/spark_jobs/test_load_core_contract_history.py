"""
Unit tests for CoreContractHistorySparkJob.

Tests verify that the job correctly transforms CDC transactional data into
the fixed 13-column narrow event-log schema used by contract_history.
"""

import json
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from pyspark.sql.types import (
    BooleanType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from pyspark.sql.utils import AnalysisException

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

    def test_payload_is_null_when_aud_config_disabled(
        self,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        # arrange — aud_config is absent from the mock config (returns None)
        job = CoreContractHistorySparkJob()
        args = _make_args()
        with patch(
            "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_contract_df,
        ):
            # act
            result = job.create_core_model(spark_session, args)

        # assert — no aud_config in mock → payload stays NULL for all rows
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
        assert "ev_id_house" not in update_event_names, (
            "id_house did not change in the update row — should not emit an event"
        )


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
            assert len(row["id_event"]) == 64, (
                f"Expected SHA-256 hex (64 chars), got {len(row['id_event'])}"
            )


class TestMergeStrategyConfig:
    def test_merge_on_historical_uses_natural_key_with_partition_columns(
        self, mock_configuration_service_history
    ):
        job = CoreContractHistorySparkJob()
        merge_on = job.get_config("merge_on_historical", required=True)

        assert merge_on == [
            "id_contract",
            "event_name",
            "ts_transaction",
            "year",
            "month",
            "day",
        ]

    def test_when_matched_update_condition_is_false(
        self, mock_configuration_service_history
    ):
        job = CoreContractHistorySparkJob()
        condition = job.get_config(
            "when_matched_update_condition_historical",
            required=False,
            default=None,
        )

        assert condition == "FALSE"


class TestTargetTableEmptyDetection:
    def test_returns_true_when_table_does_not_exist(self, spark_session):
        job = CoreContractHistorySparkJob()

        result = job._is_target_table_empty(
            spark_session, "nonexistent_db.nonexistent_table"
        )

        assert result is True

    def test_returns_true_on_analysis_exception(self, spark_session):
        job = CoreContractHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.side_effect = AnalysisException(
            "Table not found",
        )

        result = job._is_target_table_empty(mock_spark, "bad_db.bad_table")

        assert result is True

    def test_returns_true_when_table_is_empty(self):
        job = CoreContractHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = True

        result = job._is_target_table_empty(mock_spark, "db.empty_table")

        assert result is True

    def test_returns_false_when_table_has_data(self):
        job = CoreContractHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = False

        result = job._is_target_table_empty(mock_spark, "db.populated_table")

        assert result is False


AUD_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
        StructField("REV", LongType(), True),
        StructField("rEVTYPE", IntegerType(), True),
        StructField("status_MOD", BooleanType(), True),
        StructField("ts_cdc_transaction", TimestampType(), True),
        StructField("ts_revision", TimestampType(), True),
        StructField("revision_reason", StringType(), True),
        StructField("aud_user_id", LongType(), True),
    ]
)

AUD_CONFIG_ENABLED = {
    "aud_table": "test.contrato_aud",
    "aud_id_col": "id",
    "revision_entity_table": "test.usuariorevisionentity",
    "revision_reason_col": "motivo",
    "revision_user_id_col": "usuario_id",
    "revision_ts_col": "timestamp",
    "revision_ts_is_epoch_ms": True,
    "revision_pk_col": "REV",
    "revision_type_col": "rEVTYPE",
    "enabled": True,
}

HISTORICAL_EVENT_CONFIGS_WITH_MOD = [
    {
        "tracked_col": "status",
        "target_col": "status",
        "target_type": "string",
        "aud_mod_col": "status_MOD",
    },
]

CONFIG_MAP_WITH_AUD = {
    "ENTITY_TYPE": "CONTRACT",
    "CONTRACT_TRANSACTIONAL_TABLE": "test.transactional_contrato",
    "merge_on_historical": [
        "id_contract",
        "event_name",
        "ts_transaction",
        "year",
        "month",
        "day",
    ],
    "when_matched_update_condition_historical": "FALSE",
    "event_configs": HISTORICAL_EVENT_CONFIGS_WITH_MOD,
    "aud_config": AUD_CONFIG_ENABLED,
}


def _aud_config_side_effect(key, required=False, default=None):
    if key in CONFIG_MAP_WITH_AUD:
        return CONFIG_MAP_WITH_AUD[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


class TestCoreContractHistoryAudPayload:
    """Tests that AUD enrichment is wired correctly in the spark job."""

    TS_CREATE = __import__("datetime").datetime(2026, 1, 10, 8, 0, 0)
    TS_UPDATE = __import__("datetime").datetime(2026, 1, 11, 9, 0, 0)
    TS_REVISION = __import__("datetime").datetime(2026, 1, 11, 9, 0, 1)

    @staticmethod
    def _minimal_cdc_schema():
        return StructType(
            [
                StructField("id", StringType(), True),
                StructField("status", StringType(), True),
                StructField("op_cdc", StringType(), True),
                StructField("ts_database_transaction", TimestampType(), True),
                StructField("ts_cdc_transaction", TimestampType(), True),
            ]
        )

    def test_payload_is_non_null_when_aud_config_enabled_and_match_found(
        self, spark_session
    ):
        schema = self._minimal_cdc_schema()
        cdc_df = spark_session.createDataFrame(
            [
                ("100", "Ativo", "c", self.TS_CREATE, self.TS_CREATE),
                ("100", "Finalizado", "u", self.TS_UPDATE, self.TS_UPDATE),
            ],
            schema,
        )
        aud_data = [
            (
                "100",
                self.TS_UPDATE,
                9001,
                1,
                True,
                self.TS_UPDATE,
                self.TS_REVISION,
                None,
                123,
            ),
        ]
        aud_df = spark_session.createDataFrame(aud_data, AUD_SCHEMA)

        job = CoreContractHistorySparkJob()
        args = _make_args()

        with (
            patch(
                "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
                ".CoreContractHistorySparkJob.get_config",
                side_effect=_aud_config_side_effect,
            ),
            patch(
                "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
                ".HistoricalHelper.load_transactional_data",
                return_value=cdc_df,
            ),
            patch(
                "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
                ".HistoricalHelper.load_aud_revision_data",
                return_value=aud_df,
            ),
        ):
            result = job.create_core_model(spark_session, args)

        update_rows = [
            r for r in result.collect() if r["ts_transaction"] == self.TS_UPDATE
        ]
        assert len(update_rows) == 1
        assert update_rows[0]["payload"] is not None
        payload = json.loads(update_rows[0]["payload"])
        assert payload["op_cdc"] == "u"
        assert payload["rev"] == 9001

    def test_payload_remains_null_when_no_aud_match(self, spark_session):
        schema = self._minimal_cdc_schema()
        cdc_df = spark_session.createDataFrame(
            [("200", "Ativo", "c", self.TS_CREATE, self.TS_CREATE)],
            schema,
        )
        aud_df = spark_session.createDataFrame([], AUD_SCHEMA)

        job = CoreContractHistorySparkJob()
        args = _make_args()

        with (
            patch(
                "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
                ".CoreContractHistorySparkJob.get_config",
                side_effect=_aud_config_side_effect,
            ),
            patch(
                "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
                ".HistoricalHelper.load_transactional_data",
                return_value=cdc_df,
            ),
            patch(
                "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
                ".HistoricalHelper.load_aud_revision_data",
                return_value=aud_df,
            ),
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["payload"] is None


class TestRunPipelineBypass:
    def _make_pipeline_args(self):
        return SimpleNamespace(
            table_name="contract_history",
            load_start_date="2026-01-01",
            load_end_date="2026-02-01",
            partitions="['year', 'month', 'day']",
            schema="core_contract",
            bucket="test-bucket",
        )

    @patch(
        "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
        ".DataFrameDeltaTableLoaderPipeline"
    )
    def test_uses_direct_write_when_target_is_empty(
        self,
        mock_pipeline_cls,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        job = CoreContractHistorySparkJob()
        args = self._make_pipeline_args()

        with (
            patch.object(job, "_is_target_table_empty", return_value=True),
            patch.object(job, "setup_table_privileges", return_value=None),
        ):
            job.run_pipeline(transactional_contract_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] is None
        assert call_kwargs["when_matched_update_condition"] is None

    @patch(
        "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
        ".DataFrameDeltaTableLoaderPipeline"
    )
    def test_uses_partition_scoped_merge_when_target_has_data(
        self,
        mock_pipeline_cls,
        spark_session,
        transactional_contract_df,
        mock_configuration_service_history,
    ):
        job = CoreContractHistorySparkJob()
        args = self._make_pipeline_args()

        with (
            patch.object(job, "_is_target_table_empty", return_value=False),
            patch.object(job, "setup_table_privileges", return_value=None),
        ):
            job.run_pipeline(transactional_contract_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] == [
            "id_contract",
            "event_name",
            "ts_transaction",
            "year",
            "month",
            "day",
        ]
        assert call_kwargs["when_matched_update_condition"] == "FALSE"
