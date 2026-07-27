"""Unit tests for HistoricalHelper AUD revision loading (single and multi-source)."""

from datetime import datetime
from types import SimpleNamespace

import pytest
from pyspark.sql.types import (
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.core_models.helpers.historical_helper import (
    DEFAULT_TRANSACTIONAL_ENVERS_CONFIG,
    HistoricalHelper,
)

AUD_TABLE = "test.contrato_aud"
URE_TABLE = "test.usuariorevisionentity"

AUD_SCHEMA = StructType(
    [
        StructField("id", LongType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
        StructField("REV", LongType(), True),
        StructField("rEVTYPE", IntegerType(), True),
        StructField("status_MOD", StringType(), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)

URE_TRANSACTIONAL_SCHEMA = StructType(
    [
        StructField("id", LongType(), True),
        StructField("timestamp", LongType(), True),
        StructField("usuario_id", LongType(), True),
        StructField("motivo", StringType(), True),
    ]
)

URE_CLEAN_SCHEMA = StructType(
    [
        StructField("id", LongType(), True),
        StructField("ts_revision", TimestampType(), True),
        StructField("id_user", LongType(), True),
        StructField("reason", StringType(), True),
    ]
)

TS_AUD = datetime(2026, 1, 11, 9, 0, 0)
TS_REVISION = datetime(2026, 1, 11, 9, 0, 1)
TS_REVISION_EPOCH_MS = int(TS_REVISION.timestamp() * 1000)
BAD_MIGRATION_TS = 20220801123000

ARGS = SimpleNamespace(load_start_date="2026-01-11", load_end_date="2026-01-11")

# Only aud_table / aud_id_col / enabled are entity-specific; the rest are
# expected to come from HistoricalHelper.DEFAULT_TRANSACTIONAL_ENVERS_CONFIG
# (see TestResolveAudConfig below). Tests below still override
# revision_entity_table to point at the local temp view registered for the
# test.
TRANSACTIONAL_AUD_CONFIG = {
    "enabled": True,
    "aud_table": AUD_TABLE,
    "aud_id_col": "id",
}

# Clean AUD layer uses a different revision-entity table and column-naming
# convention, so every default that differs from the transactional
# convention must be explicitly overridden here.
CLEAN_AUD_CONFIG = {
    "enabled": True,
    "aud_table": AUD_TABLE,
    "aud_id_col": "id",
    "revision_entity_table": "test.user_revision_entity",
    "revision_reason_col": "reason",
    "revision_pk_col": "REV",
    "revision_user_id_col": "id_user",
    "revision_ts_col": "ts_revision",
    "revision_ts_is_epoch_ms": False,
}


def _register_tables(spark_session, aud_rows, ure_rows, ure_schema):
    aud_df = spark_session.createDataFrame(aud_rows, AUD_SCHEMA)
    ure_df = spark_session.createDataFrame(ure_rows, ure_schema)
    aud_df.createOrReplaceTempView("contrato_aud")
    ure_df.createOrReplaceTempView("usuariorevisionentity")
    return aud_df, ure_df


class TestResolveAudConfig:
    def test_fills_in_transactional_envers_defaults_when_omitted(self):
        # arrange
        entity_specific_config = {
            "enabled": True,
            "aud_table": "test.contrato_aud",
            "aud_id_col": "id",
        }

        # act
        resolved = HistoricalHelper.resolve_aud_config(entity_specific_config)

        # assert
        for key, default_value in DEFAULT_TRANSACTIONAL_ENVERS_CONFIG.items():
            assert resolved[key] == default_value
        assert resolved["aud_table"] == "test.contrato_aud"
        assert resolved["aud_id_col"] == "id"
        assert resolved["enabled"] is True

    def test_entity_specific_overrides_win_over_defaults(self):
        # arrange
        clean_layer_config = {
            "enabled": True,
            "aud_table": "test.contract_aud",
            "aud_id_col": "id_contract",
            "revision_entity_table": "test.user_revision_entity",
            "revision_reason_col": "reason",
            "revision_user_id_col": "id_user",
            "revision_ts_col": "ts_revision",
            "revision_ts_is_epoch_ms": False,
        }

        # act
        resolved = HistoricalHelper.resolve_aud_config(clean_layer_config)

        # assert
        assert resolved["revision_entity_table"] == "test.user_revision_entity"
        assert resolved["revision_reason_col"] == "reason"
        assert resolved["revision_user_id_col"] == "id_user"
        assert resolved["revision_ts_col"] == "ts_revision"
        assert resolved["revision_ts_is_epoch_ms"] is False
        # Untouched defaults still apply
        assert resolved["revision_pk_col"] == "REV"
        assert resolved["revision_type_col"] == "rEVTYPE"


class TestLoadAudRevisionData:
    def test_joins_transactional_revision_entity_with_epoch_ms_timestamp(
        self, spark_session
    ):
        # arrange
        _register_tables(
            spark_session,
            aud_rows=[(100, TS_AUD, 42, 1, True, 2026, 1, 11)],
            ure_rows=[(42, TS_REVISION_EPOCH_MS, 999, "[SYSTEM] update")],
            ure_schema=URE_TRANSACTIONAL_SCHEMA,
        )
        config = {
            **TRANSACTIONAL_AUD_CONFIG,
            "aud_table": "contrato_aud",
            "revision_entity_table": "usuariorevisionentity",
        }

        # act
        result = HistoricalHelper.load_aud_revision_data(spark_session, config, ARGS)

        # assert
        row = result.collect()[0]
        assert row.REV == 42
        assert row.revision_reason == "[SYSTEM] update"
        assert row.aud_user_id == 999
        assert row.ts_revision == TS_REVISION

    def test_applies_bad_migration_timestamp_fix(self, spark_session):
        # arrange
        _register_tables(
            spark_session,
            aud_rows=[(100, TS_AUD, 7, 1, True, 2026, 1, 11)],
            ure_rows=[(7, BAD_MIGRATION_TS, 123, "legacy")],
            ure_schema=URE_TRANSACTIONAL_SCHEMA,
        )
        config = {
            **TRANSACTIONAL_AUD_CONFIG,
            "aud_table": "contrato_aud",
            "revision_entity_table": "usuariorevisionentity",
        }

        # act
        result = HistoricalHelper.load_aud_revision_data(spark_session, config, ARGS)

        # assert
        row = result.collect()[0]
        assert row.ts_revision == datetime(2022, 8, 1, 12, 30, 0)

    def test_filters_revision_entity_to_rev_ids_in_aud_window(self, spark_session):
        # arrange
        _register_tables(
            spark_session,
            aud_rows=[(100, TS_AUD, 42, 1, True, 2026, 1, 11)],
            ure_rows=[
                (42, TS_REVISION_EPOCH_MS, 999, "matched"),
                (99, TS_REVISION_EPOCH_MS, 111, "out_of_window"),
            ],
            ure_schema=URE_TRANSACTIONAL_SCHEMA,
        )
        config = {
            **TRANSACTIONAL_AUD_CONFIG,
            "aud_table": "contrato_aud",
            "revision_entity_table": "usuariorevisionentity",
        }

        # act
        result = HistoricalHelper.load_aud_revision_data(spark_session, config, ARGS)

        # assert
        row = result.collect()[0]
        assert row.revision_reason == "matched"

    def test_clean_revision_entity_uses_timestamp_column_directly(self, spark_session):
        # arrange
        aud_df = spark_session.createDataFrame(
            [(100, TS_AUD, 42, 1, True, 2026, 1, 11)], AUD_SCHEMA
        )
        ure_df = spark_session.createDataFrame(
            [(42, TS_REVISION, 999, "clean reason")], URE_CLEAN_SCHEMA
        )
        aud_df.createOrReplaceTempView("contrato_aud")
        ure_df.createOrReplaceTempView("user_revision_entity")
        config = {
            **CLEAN_AUD_CONFIG,
            "aud_table": "contrato_aud",
            "revision_entity_table": "user_revision_entity",
        }

        # act
        result = HistoricalHelper.load_aud_revision_data(spark_session, config, ARGS)

        # assert
        row = result.collect()[0]
        assert row.ts_revision == TS_REVISION
        assert row.revision_reason == "clean reason"
        assert row.aud_user_id == 999

    def test_returns_none_when_aud_config_disabled(self, spark_session):
        # act
        result = HistoricalHelper.load_aud_revision_data(
            spark_session, {"enabled": False}, ARGS
        )

        # assert
        assert result is None


class TestLoadAudRevisionDatasets:
    def _register_two_aud_sources(self, spark_session):
        _register_tables(
            spark_session,
            aud_rows=[(100, TS_AUD, 42, 1, True, 2026, 1, 11)],
            ure_rows=[(42, TS_REVISION_EPOCH_MS, 999, "contract reason")],
            ure_schema=URE_TRANSACTIONAL_SCHEMA,
        )
        imovel_aud_df = spark_session.createDataFrame(
            [(200, TS_AUD, 42, 1, True, 2026, 1, 11)], AUD_SCHEMA
        )
        imovel_aud_df.createOrReplaceTempView("imovel_aud")

    def test_loads_multiple_named_sources(self, spark_session):
        # arrange
        self._register_two_aud_sources(spark_session)
        aud_configs = [
            {
                "name": "contract",
                "enabled": True,
                "aud_table": "contrato_aud",
                "aud_id_col": "id",
                "revision_entity_table": "usuariorevisionentity",
            },
            {
                "name": "imovel",
                "enabled": True,
                "aud_table": "imovel_aud",
                "aud_id_col": "id",
                "revision_entity_table": "usuariorevisionentity",
            },
        ]

        # act
        result = HistoricalHelper.load_aud_revision_datasets(
            spark_session, aud_configs, ARGS
        )

        # assert
        assert set(result.keys()) == {"contract", "imovel"}
        assert result["contract"].collect()[0].id == 100
        assert result["imovel"].collect()[0].id == 200

    def test_excludes_disabled_entries(self, spark_session):
        # arrange
        self._register_two_aud_sources(spark_session)
        aud_configs = [
            {
                "name": "contract",
                "enabled": True,
                "aud_table": "contrato_aud",
                "aud_id_col": "id",
                "revision_entity_table": "usuariorevisionentity",
            },
            {
                "name": "imovel",
                "enabled": False,
                "aud_table": "imovel_aud",
                "aud_id_col": "id",
            },
        ]

        # act
        result = HistoricalHelper.load_aud_revision_datasets(
            spark_session, aud_configs, ARGS
        )

        # assert
        assert set(result.keys()) == {"contract"}

    def test_raises_on_duplicate_name(self, spark_session):
        # arrange
        aud_configs = [
            {"name": "imovel", "enabled": False},
            {"name": "imovel", "enabled": False},
        ]

        # act / assert
        with pytest.raises(ValueError, match="duplicate name"):
            HistoricalHelper.load_aud_revision_datasets(
                spark_session, aud_configs, ARGS
            )

    def test_raises_on_missing_name(self, spark_session):
        # arrange
        aud_configs = [{"enabled": False}]

        # act / assert
        with pytest.raises(ValueError, match="non-empty 'name'"):
            HistoricalHelper.load_aud_revision_datasets(
                spark_session, aud_configs, ARGS
            )
