"""Unit tests for HistoryBuilder."""

import json
from datetime import datetime

import pytest
from pyspark.sql.types import (
    BooleanType,
    DoubleType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.core_models.helpers.history_builder import HistoryBuilder

# ---------------------------------------------------------------------------
# Shared schema / configs for default_value tests
# ---------------------------------------------------------------------------

DEFAULT_VALUE_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("relistingEnabled", BooleanType(), True),
        StructField("op_cdc", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
    ]
)

DEFAULT_VALUE_EVENT_CONFIGS = [
    {
        "tracked_col": "relistingEnabled",
        "target_col": "is_relisting_enabled",
        "target_type": "boolean",
        "default_value": "false",
    }
]

JSON_DERIVED_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("contractRentModel", StringType(), True),
        StructField("op_cdc", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
    ]
)

JSON_DERIVED_EVENT_CONFIGS = [
    {
        "tracked_col": "rentalAdministrator",
        "source_col": "contractRentModel",
        "json_path": "$.rentalAdministrator",
        "target_col": "rental_administrator",
        "target_type": "string",
        "default_value": "QUINTOANDAR",
    }
]


EXPECTED_COLUMNS = {
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

EVENT_CONFIGS = [
    {"tracked_col": "status", "event_name": "ev_STATUS"},
    {"tracked_col": "rent", "event_name": "ev_RENT_VALUE"},
]

TRANSACTIONAL_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("status", StringType(), True),
        StructField("rent", DoubleType(), True),
        StructField("op_cdc", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
    ]
)

SOURCE_TABLE = "datalake_ebdb_transactional.contrato"


@pytest.fixture
def transactional_insert_df(spark_session):
    """Single create event -- all tracked columns should emit."""
    data = [
        ("100", "Ativo", 2500.0, "c", datetime(2026, 1, 10, 8, 0, 0)),
    ]
    return spark_session.createDataFrame(data, TRANSACTIONAL_SCHEMA)


@pytest.fixture
def transactional_update_df(spark_session):
    """Two transactions for the same entity: create then update status."""
    data = [
        ("100", "Ativo", 2500.0, "c", datetime(2026, 1, 10, 8, 0, 0)),
        ("100", "Finalizado", 2500.0, "u", datetime(2026, 1, 11, 9, 0, 0)),
    ]
    return spark_session.createDataFrame(data, TRANSACTIONAL_SCHEMA)


@pytest.fixture
def transactional_no_change_df(spark_session):
    """Create then update with identical values -- update should emit nothing."""
    data = [
        ("200", "Ativo", 1800.0, "c", datetime(2026, 2, 1, 10, 0, 0)),
        ("200", "Ativo", 1800.0, "u", datetime(2026, 2, 2, 10, 0, 0)),
    ]
    return spark_session.createDataFrame(data, TRANSACTIONAL_SCHEMA)


@pytest.fixture
def transactional_delete_df(spark_session):
    """Create then delete -- delete should emit for all tracked columns."""
    data = [
        ("300", "Ativo", 3000.0, "c", datetime(2026, 3, 1, 10, 0, 0)),
        ("300", "Ativo", 3000.0, "d", datetime(2026, 3, 5, 12, 0, 0)),
    ]
    return spark_session.createDataFrame(data, TRANSACTIONAL_SCHEMA)


@pytest.fixture
def transactional_null_change_df(spark_session):
    """Create with NULL rent, then update setting rent to a value."""
    data = [
        ("400", "Ativo", None, "c", datetime(2026, 4, 1, 10, 0, 0)),
        ("400", "Ativo", 1500.0, "u", datetime(2026, 4, 2, 10, 0, 0)),
    ]
    return spark_session.createDataFrame(data, TRANSACTIONAL_SCHEMA)


@pytest.fixture
def transactional_value_to_null_df(spark_session):
    """Create with a rent value, then update setting rent to NULL."""
    data = [
        ("500", "Ativo", 2000.0, "c", datetime(2026, 5, 1, 10, 0, 0)),
        ("500", "Ativo", None, "u", datetime(2026, 5, 2, 10, 0, 0)),
    ]
    return spark_session.createDataFrame(data, TRANSACTIONAL_SCHEMA)


TYPED_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("is_active", BooleanType(), True),
        StructField("count", IntegerType(), True),
        StructField("op_cdc", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
    ]
)

TYPED_EVENT_CONFIGS = [
    {"tracked_col": "is_active", "event_name": "ev_IS_ACTIVE"},
    {"tracked_col": "count", "event_name": "ev_COUNT"},
]


@pytest.fixture
def transactional_typed_df(spark_session):
    """Single create with boolean and integer columns for type-cast tests."""
    data = [
        ("600", True, 42, "c", datetime(2026, 6, 1, 10, 0, 0)),
    ]
    return spark_session.createDataFrame(data, TYPED_SCHEMA)


@pytest.fixture
def empty_transactional_df(spark_session):
    """Empty DataFrame with the transactional schema."""
    return spark_session.createDataFrame([], TRANSACTIONAL_SCHEMA)


class TestHistoryBuilderInsert:
    def test_insert_emits_events_for_all_tracked_columns(self, transactional_insert_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        rows = result.collect()
        event_names = {r["event_name"] for r in rows}
        assert event_names == {"ev_STATUS", "ev_RENT_VALUE"}
        assert len(rows) == 2

    def test_insert_has_correct_schema(self, transactional_insert_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        assert set(result.columns) == EXPECTED_COLUMNS
        assert len(result.columns) == 13

    def test_insert_payload_is_null(self, transactional_insert_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        for row in result.collect():
            assert row["payload"] is None

    def test_insert_value_is_cast_to_string(self, transactional_insert_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        rent_row = [r for r in result.collect() if r["event_name"] == "ev_RENT_VALUE"][
            0
        ]
        assert isinstance(rent_row["value"], str)
        assert rent_row["value"] == "2500.0"


class TestHistoryBuilderUpdate:
    def test_update_with_change_emits_only_changed_column(
        self, transactional_update_df
    ):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_update_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- create emits 2 events, update emits 1 (only status changed)
        rows = result.collect()
        assert len(rows) == 3

        update_rows = [
            r for r in rows if r["ts_transaction"] == datetime(2026, 1, 11, 9, 0, 0)
        ]
        assert len(update_rows) == 1
        assert update_rows[0]["event_name"] == "ev_STATUS"
        assert update_rows[0]["value"] == "Finalizado"

    def test_update_with_no_change_emits_no_events(self, transactional_no_change_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_no_change_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- only the create emits events (2), the update emits 0
        rows = result.collect()
        update_rows = [
            r for r in rows if r["ts_transaction"] == datetime(2026, 2, 2, 10, 0, 0)
        ]
        assert len(update_rows) == 0
        assert len(rows) == 2

    def test_update_null_to_value_emits_event(self, transactional_null_change_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_null_change_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- update should detect NULL -> 1500.0 as a change
        rows = result.collect()
        update_rent_rows = [
            r
            for r in rows
            if r["ts_transaction"] == datetime(2026, 4, 2, 10, 0, 0)
            and r["event_name"] == "ev_RENT_VALUE"
        ]
        assert len(update_rent_rows) == 1
        assert update_rent_rows[0]["value"] == "1500.0"

    def test_update_value_to_null_emits_event(self, transactional_value_to_null_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_value_to_null_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- update should detect 2000.0 -> NULL as a change
        rows = result.collect()
        update_rent_rows = [
            r
            for r in rows
            if r["ts_transaction"] == datetime(2026, 5, 2, 10, 0, 0)
            and r["event_name"] == "ev_RENT_VALUE"
        ]
        assert len(update_rent_rows) == 1
        assert update_rent_rows[0]["value"] is None


class TestHistoryBuilderDelete:
    def test_delete_emits_events_for_all_tracked_columns(self, transactional_delete_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_delete_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- create=2 events, delete=2 events
        rows = result.collect()
        delete_rows = [
            r for r in rows if r["ts_transaction"] == datetime(2026, 3, 5, 12, 0, 0)
        ]
        assert len(delete_rows) == 2
        assert {r["event_name"] for r in delete_rows} == {
            "ev_STATUS",
            "ev_RENT_VALUE",
        }


class TestHistoryBuilderKeys:
    def test_id_event_is_deterministic(self, transactional_insert_df):
        # act -- run twice
        result1 = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        result2 = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        ids1 = sorted([r["id_event"] for r in result1.collect()])
        ids2 = sorted([r["id_event"] for r in result2.collect()])
        assert ids1 == ids2

    def test_id_event_is_sha256_hex(self, transactional_insert_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        for row in result.collect():
            assert row["id_event"] is not None
            assert len(row["id_event"]) == 64

    def test_sk_entity_is_non_null_sha256(self, transactional_insert_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        for row in result.collect():
            assert row["sk_core_contract"] is not None
            assert len(row["sk_core_contract"]) == 64


class TestHistoryBuilderEdgeCases:
    def test_empty_dataframe_returns_empty_with_correct_schema(
        self, empty_transactional_df
    ):
        # act
        result = HistoryBuilder.build_history_for_columns(
            empty_transactional_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        assert result.count() == 0
        assert set(result.columns) == EXPECTED_COLUMNS

    def test_empty_event_configs_raises_value_error(self, transactional_insert_df):
        # act / assert
        with pytest.raises(ValueError, match="event_configs must not be empty"):
            HistoryBuilder.build_history_for_columns(
                transactional_insert_df,
                entity_name="contract",
                id_col="id",
                ts_col="ts_database_transaction",
                op_col="op_cdc",
                event_configs=[],
            )

    def test_invalid_event_config_raises_value_error(self, transactional_insert_df):
        # act / assert
        with pytest.raises(ValueError, match="event_name' or 'target_col"):
            HistoryBuilder.build_history_for_columns(
                transactional_insert_df,
                entity_name="contract",
                id_col="id",
                ts_col="ts_database_transaction",
                op_col="op_cdc",
                event_configs=[{"tracked_col": "status"}],
            )

    def test_json_derived_config_requires_source_col_and_json_path(
        self, transactional_insert_df
    ):
        # act / assert -- json_path without source_col should fail fast
        with pytest.raises(
            ValueError, match="must declare both 'source_col' and 'json_path'"
        ):
            HistoryBuilder.build_history_for_columns(
                transactional_insert_df,
                entity_name="contract",
                id_col="id",
                ts_col="ts_database_transaction",
                op_col="op_cdc",
                event_configs=[
                    {
                        "tracked_col": "rentalAdministrator",
                        "json_path": "$.rentalAdministrator",
                        "target_col": "rental_administrator",
                        "target_type": "string",
                    }
                ],
            )

    def test_event_name_derived_from_target_col_when_omitted(
        self, transactional_insert_df
    ):
        event_configs = [
            {"tracked_col": "status", "target_col": "status", "target_type": "string"},
            {"tracked_col": "rent", "target_col": "rent", "target_type": "double"},
        ]
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        event_names = {r["event_name"] for r in result.collect()}
        assert event_names == {"ev_status", "ev_rent"}

    def test_explicit_event_name_overrides_target_col_derivation(
        self, transactional_insert_df
    ):
        event_configs = [
            {
                "tracked_col": "status",
                "event_name": "ev_STATUS",
                "target_col": "contract_status",
                "target_type": "string",
            },
        ]
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        assert {r["event_name"] for r in result.collect()} == {"ev_STATUS"}

    def test_event_origin_and_event_type_propagated(self, transactional_insert_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert
        for row in result.collect():
            assert row["event_type"] == "cdc"
            assert row["event_origin"] == SOURCE_TABLE

    def test_partition_columns_match_transaction_timestamp(
        self, transactional_insert_df
    ):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_insert_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- ts is 2026-01-10
        row = result.first()
        assert row["year"] == 2026
        assert row["month"] == 1
        assert row["day"] == 10

    def test_value_cast_to_string_for_boolean_type(self, transactional_typed_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_typed_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=TYPED_EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- boolean True must be cast to string
        bool_row = [r for r in result.collect() if r["event_name"] == "ev_IS_ACTIVE"][0]
        assert isinstance(bool_row["value"], str)
        assert bool_row["value"] == "true"

    def test_value_cast_to_string_for_integer_type(self, transactional_typed_df):
        # act
        result = HistoryBuilder.build_history_for_columns(
            transactional_typed_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=TYPED_EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        # assert -- integer 42 must be cast to string
        int_row = [r for r in result.collect() if r["event_name"] == "ev_COUNT"][0]
        assert isinstance(int_row["value"], str)
        assert int_row["value"] == "42"


class TestHistoryBuilderDefaultValue:
    """Tests for event_configs entries that declare a default_value.

    Mirrors the is_relisting_enabled / relistingEnabled transformation on
    core_contract_history: null → false so that null-to-null transitions
    do not emit spurious events and stored values align with the current-state
    model (core_contract.contract uses coalesce(is_relisting_enabled, false)).
    """

    def _build(self, spark_session, data):
        df = spark_session.createDataFrame(data, DEFAULT_VALUE_SCHEMA)
        return HistoryBuilder.build_history_for_columns(
            df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=DEFAULT_VALUE_EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )

    def test_create_with_null_stores_false_as_value(self, spark_session):
        # arrange -- contract created with relistingEnabled = null
        data = [("1", None, "c", datetime(2026, 1, 1, 8, 0, 0))]
        result = self._build(spark_session, data)
        rows = result.collect()
        # create always emits; default coalesces null → false
        assert len(rows) == 1
        assert rows[0]["event_name"] == "ev_is_relisting_enabled"
        assert rows[0]["value"] == "false"

    def test_update_null_to_null_emits_no_event(self, spark_session):
        # arrange -- relisting stays null across an update
        data = [
            ("2", None, "c", datetime(2026, 1, 1, 8, 0, 0)),
            ("2", None, "u", datetime(2026, 1, 2, 8, 0, 0)),
        ]
        result = self._build(spark_session, data)
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2026, 1, 2, 8, 0, 0)
        ]
        # null → null = false → false after coalesce: no change, no event
        assert len(update_rows) == 0

    def test_update_null_to_false_emits_no_event(self, spark_session):
        # arrange -- relisting changes from null to explicit false (same effective value)
        data = [
            ("3", None, "c", datetime(2026, 1, 1, 8, 0, 0)),
            ("3", False, "u", datetime(2026, 1, 2, 8, 0, 0)),
        ]
        result = self._build(spark_session, data)
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2026, 1, 2, 8, 0, 0)
        ]
        # null → false = false → false after coalesce: same effective value, no event
        assert len(update_rows) == 0

    def test_update_null_to_true_emits_event_with_true_value(self, spark_session):
        # arrange -- relisting becomes enabled
        data = [
            ("4", None, "c", datetime(2026, 1, 1, 8, 0, 0)),
            ("4", True, "u", datetime(2026, 1, 2, 8, 0, 0)),
        ]
        result = self._build(spark_session, data)
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2026, 1, 2, 8, 0, 0)
        ]
        # null → true = false → true after coalesce: effective change detected
        assert len(update_rows) == 1
        assert update_rows[0]["event_name"] == "ev_is_relisting_enabled"
        assert update_rows[0]["value"] == "true"

    def test_update_true_to_null_emits_event_with_false_value(self, spark_session):
        # arrange -- relisting reverts to null (same effective value as false)
        data = [
            ("5", True, "c", datetime(2026, 1, 1, 8, 0, 0)),
            ("5", None, "u", datetime(2026, 1, 2, 8, 0, 0)),
        ]
        result = self._build(spark_session, data)
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2026, 1, 2, 8, 0, 0)
        ]
        # true → null = true → false after coalesce: this IS a change
        # (effectively enabled → disabled), so an event should be emitted
        assert len(update_rows) == 1
        assert update_rows[0]["value"] == "false"

    def test_column_without_default_value_is_unaffected(self, spark_session):
        # arrange -- mix: one column with default_value, one without
        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("relistingEnabled", BooleanType(), True),
                StructField("rent", DoubleType(), True),
                StructField("op_cdc", StringType(), True),
                StructField("ts_database_transaction", TimestampType(), True),
            ]
        )
        mixed_configs = [
            {
                "tracked_col": "relistingEnabled",
                "target_col": "is_relisting_enabled",
                "target_type": "boolean",
                "default_value": "false",
            },
            {"tracked_col": "rent", "event_name": "ev_rent"},
        ]
        data = [("6", None, None, "c", datetime(2026, 2, 1, 8, 0, 0))]
        df = spark_session.createDataFrame(data, schema)
        result = HistoryBuilder.build_history_for_columns(
            df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=mixed_configs,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )
        rows = {r["event_name"]: r for r in result.collect()}
        # relistingEnabled: null → "false" via default_value
        assert rows["ev_is_relisting_enabled"]["value"] == "false"
        # rent: null stays null, no default applied
        assert rows["ev_rent"]["value"] is None


class TestHistoryBuilderJsonDerivedField:
    """Tests for event_configs entries that derive tracked values from JSON paths."""

    def _build(self, spark_session, data):
        df = spark_session.createDataFrame(data, JSON_DERIVED_SCHEMA)
        return HistoryBuilder.build_history_for_columns(
            df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=JSON_DERIVED_EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )

    def test_create_with_missing_json_path_uses_default_value(self, spark_session):
        # arrange -- missing rentalAdministrator path should fallback to QUINTOANDAR
        data = [("10", '{"anotherField":"x"}', "c", datetime(2026, 1, 1, 8, 0, 0))]
        result = self._build(spark_session, data)

        # assert
        rows = result.collect()
        assert len(rows) == 1
        assert rows[0]["event_name"] == "ev_rental_administrator"
        assert rows[0]["value"] == "QUINTOANDAR"

    def test_update_changing_json_path_value_emits_event(self, spark_session):
        # arrange -- update changes rentalAdministrator from default to explicit value
        data = [
            (
                "11",
                '{"rentalAdministrator":"QUINTOANDAR","anotherField":"x"}',
                "c",
                datetime(2026, 1, 1, 8, 0, 0),
            ),
            (
                "11",
                '{"rentalAdministrator":"IMOBILIARIA","anotherField":"x"}',
                "u",
                datetime(2026, 1, 2, 8, 0, 0),
            ),
        ]
        result = self._build(spark_session, data)

        # assert
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2026, 1, 2, 8, 0, 0)
        ]
        assert len(update_rows) == 1
        assert update_rows[0]["event_name"] == "ev_rental_administrator"
        assert update_rows[0]["value"] == "IMOBILIARIA"

    def test_update_changing_other_json_fields_emits_no_event(self, spark_session):
        # arrange -- payload changes but tracked JSON path keeps the same value
        data = [
            (
                "12",
                '{"rentalAdministrator":"QUINTOANDAR","anotherField":"x"}',
                "c",
                datetime(2026, 1, 1, 8, 0, 0),
            ),
            (
                "12",
                '{"rentalAdministrator":"QUINTOANDAR","anotherField":"y"}',
                "u",
                datetime(2026, 1, 2, 8, 0, 0),
            ),
        ]
        result = self._build(spark_session, data)

        # assert -- only create event, no update event for derived field
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2026, 1, 2, 8, 0, 0)
        ]
        assert len(update_rows) == 0

    def test_update_missing_json_path_to_missing_json_path_emits_no_event(
        self, spark_session
    ):
        # arrange -- both rows fallback to QUINTOANDAR after default coalesce
        data = [
            ("13", '{"anotherField":"x"}', "c", datetime(2026, 1, 1, 8, 0, 0)),
            ("13", '{"anotherField":"y"}', "u", datetime(2026, 1, 2, 8, 0, 0)),
        ]
        result = self._build(spark_session, data)

        # assert -- effective value unchanged (QUINTOANDAR -> QUINTOANDAR)
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2026, 1, 2, 8, 0, 0)
        ]
        assert len(update_rows) == 0


class TestHistoryBuilderSnapshotRead:
    """Tests for CDC snapshot/read rows (op_cdc='r')."""

    SNAPSHOT_TS = datetime(2025, 5, 12, 0, 0, 0)

    def _build(self, spark_session, data):
        df = spark_session.createDataFrame(data, TRANSACTIONAL_SCHEMA)
        return HistoryBuilder.build_history_for_columns(
            df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )

    def test_snapshot_read_baseline_emits_events(self, spark_session):
        # arrange -- first snapshot row for entity (prev is NULL)
        data = [("700", "Ativo", 2500.0, "r", self.SNAPSHOT_TS)]
        result = self._build(spark_session, data)
        rows = result.collect()

        # assert
        assert len(rows) == 2
        assert {r["event_name"] for r in rows} == {"ev_STATUS", "ev_RENT_VALUE"}

    def test_repeated_identical_snapshot_read_emits_no_extra_events(
        self, spark_session
    ):
        # arrange -- two identical r rows (re-snapshot with unchanged value)
        data = [
            ("701", "Ativo", 2500.0, "r", self.SNAPSHOT_TS),
            ("701", "Ativo", 2500.0, "r", datetime(2025, 6, 2, 0, 0, 0)),
        ]
        result = self._build(spark_session, data)
        rows = result.collect()

        # assert -- only baseline from first r; second r suppressed
        assert len(rows) == 2
        assert all(r["ts_transaction"] == self.SNAPSHOT_TS for r in rows)

    def test_snapshot_read_with_changed_value_emits_event(self, spark_session):
        # arrange -- re-snapshot reflects a value change vs prior r
        data = [
            ("702", "Ativo", 2500.0, "r", self.SNAPSHOT_TS),
            ("702", "Finalizado", 2500.0, "r", datetime(2025, 6, 2, 0, 0, 0)),
        ]
        result = self._build(spark_session, data)
        status_rows = [
            r
            for r in result.collect()
            if r["event_name"] == "ev_STATUS"
            and r["ts_transaction"] == datetime(2025, 6, 2, 0, 0, 0)
        ]

        # assert
        assert len(status_rows) == 1
        assert status_rows[0]["value"] == "Finalizado"

    def test_snapshot_read_only_entity_surfaces_in_history(self, spark_session):
        # arrange -- entity exists only via snapshot, never c/u/d
        data = [("703", "Ativo", 1800.0, "r", self.SNAPSHOT_TS)]
        result = self._build(spark_session, data)
        rows = result.collect()

        # assert
        assert len(rows) == 2
        assert all(r["id_contract"] == "703" for r in rows)

    def test_snapshot_read_followed_by_update_same_value_emits_no_extra_event(
        self, spark_session
    ):
        # arrange -- r baseline then u with identical values
        data = [
            ("704", "Ativo", 2500.0, "r", self.SNAPSHOT_TS),
            ("704", "Ativo", 2500.0, "u", datetime(2025, 6, 3, 10, 0, 0)),
        ]
        result = self._build(spark_session, data)
        update_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == datetime(2025, 6, 3, 10, 0, 0)
        ]

        # assert -- u with no value change suppressed
        assert len(update_rows) == 0
        assert len(result.collect()) == 2

    def test_two_snapshot_reads_at_same_timestamp_collapse_to_one_event(
        self, spark_session
    ):
        # arrange -- two r rows at same ts with different status
        same_ts = datetime(2025, 10, 9, 10, 31, 31)
        data = [
            ("705", "Ativo", 2500.0, "r", same_ts),
            ("705", "Finalizado", 2500.0, "r", same_ts),
        ]
        result = self._build(spark_session, data)
        status_rows = [r for r in result.collect() if r["event_name"] == "ev_STATUS"]

        # assert -- canonicalization keeps one row per (id, ts), so a single
        # status event is emitted upstream of the merge (no duplicate id_event).
        # The schema carries no tie-breaker columns, so the surviving value is
        # non-deterministic; only the grain is guaranteed.
        assert len(status_rows) == 1
        assert status_rows[0]["value"] in {"Ativo", "Finalizado"}


# ---------------------------------------------------------------------------
# AUD payload enrichment tests
# ---------------------------------------------------------------------------

AUD_EVENT_CONFIGS = [
    {
        "tracked_col": "status",
        "event_name": "ev_STATUS",
        "aud_mod_col": "status_MOD",
    },
    {
        "tracked_col": "rent",
        "event_name": "ev_RENT_VALUE",
        "aud_mod_col": "valorAluguel_MOD",
    },
]

AUD_CONFIG = {
    "aud_id_col": "id",
    "revision_pk_col": "REV",
    "revision_type_col": "rEVTYPE",
    "enabled": True,
}

AUD_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
        StructField("REV", LongType(), True),
        StructField("rEVTYPE", IntegerType(), True),
        StructField("status_MOD", BooleanType(), True),
        StructField("valorAluguel_MOD", BooleanType(), True),
        StructField("ts_cdc_transaction", TimestampType(), True),
        StructField("ts_revision", TimestampType(), True),
        StructField("revision_reason", StringType(), True),
        StructField("aud_user_id", LongType(), True),
    ]
)


# ---------------------------------------------------------------------------
# Canonicalization: collapse many CDC rows per (entity_id, ts) to one
# ---------------------------------------------------------------------------

# Region-like profile: source-recency columns (version / updated_at) plus the
# universal CDC metadata and partition columns.
CANON_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("status", StringType(), True),
        StructField("rent", DoubleType(), True),
        StructField("op_cdc", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
        StructField("version", IntegerType(), True),
        StructField("updated_at", TimestampType(), True),
        StructField("ts_cdc_transaction", TimestampType(), True),
        StructField("cdc_binlog_position", LongType(), True),
        StructField("cdc_transaction_id", StringType(), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)

# House (imovel) profile: NO version / updated_at -- only CDC metadata.
IMOVEL_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("status", StringType(), True),
        StructField("rent", DoubleType(), True),
        StructField("op_cdc", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
        StructField("ts_cdc_transaction", TimestampType(), True),
        StructField("cdc_binlog_position", LongType(), True),
        StructField("cdc_transaction_id", StringType(), True),
    ]
)


def _build_with_aud(spark_session, cdc_data, aud_data):
    """Helper: build history with AUD enrichment enabled.

    Always creates a non-None AUD DataFrame so enrichment is activated even
    when the AUD list is empty (empty ≠ disabled).
    """
    cdc_df = spark_session.createDataFrame(cdc_data, TRANSACTIONAL_SCHEMA)
    aud_df = spark_session.createDataFrame(aud_data, AUD_SCHEMA)
    return HistoryBuilder.build_history_for_columns(
        cdc_df,
        entity_name="contract",
        id_col="id",
        ts_col="ts_database_transaction",
        op_col="op_cdc",
        event_configs=AUD_EVENT_CONFIGS,
        event_type="cdc",
        event_origin=SOURCE_TABLE,
        aud_df=aud_df,
        aud_config=AUD_CONFIG,
    )


class TestHistoryBuilderAudPayload:
    """AUD enrichment: payload JSON is populated when AUD match is found."""

    TS_CREATE = datetime(2026, 1, 10, 8, 0, 0)
    TS_UPDATE = datetime(2026, 1, 11, 9, 0, 0)
    TS_REVISION = datetime(2026, 1, 11, 9, 0, 1)

    def test_update_event_payload_is_non_null_when_aud_match_found(self, spark_session):
        cdc_data = [
            ("100", "Ativo", 2500.0, "c", self.TS_CREATE),
            ("100", "Finalizado", 2500.0, "u", self.TS_UPDATE),
        ]
        aud_data = [
            (
                "100",
                self.TS_UPDATE,
                9001,
                1,
                True,  # status_MOD=true
                False,  # valorAluguel_MOD=false
                self.TS_UPDATE,  # ts_cdc_transaction
                self.TS_REVISION,
                None,
                12345,
            ),
        ]
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        update_status = [
            r
            for r in result.collect()
            if r["ts_transaction"] == self.TS_UPDATE and r["event_name"] == "ev_STATUS"
        ]
        assert len(update_status) == 1
        assert update_status[0]["payload"] is not None
        payload = json.loads(update_status[0]["payload"])
        assert payload["payload_version"] == 1
        assert payload["op_cdc"] == "u"
        assert payload["rev"] == 9001
        assert payload["rev_type"] == 1
        assert payload["aud_user_id"] == 12345
        assert "status" in payload["aud_values"]
        assert "ts_cdc_transaction" in payload

    def test_payload_is_null_when_no_aud_match(self, spark_session):
        cdc_data = [
            ("200", "Ativo", 2500.0, "c", self.TS_CREATE),
            ("200", "Finalizado", 2500.0, "u", self.TS_UPDATE),
        ]
        # AUD has no row for entity 200 at TS_UPDATE
        aud_data = []
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        update_status = [
            r
            for r in result.collect()
            if r["ts_transaction"] == self.TS_UPDATE and r["event_name"] == "ev_STATUS"
        ]
        assert len(update_status) == 1
        assert update_status[0]["payload"] is None

    def test_mod_flag_discriminator_filters_wrong_revision(self, spark_session):
        # Two AUD rows at same ts: one for status, one for rent (different mod flags).
        # The status event should match only the status revision.
        cdc_data = [
            ("300", "Ativo", 2500.0, "c", self.TS_CREATE),
            ("300", "Finalizado", 2500.0, "u", self.TS_UPDATE),
        ]
        aud_data = [
            # rev 9001: status_MOD=True, valorAluguel_MOD=False
            (
                "300",
                self.TS_UPDATE,
                9001,
                1,
                True,
                False,
                self.TS_UPDATE,
                self.TS_REVISION,
                None,
                111,
            ),
            # rev 9002: status_MOD=False, valorAluguel_MOD=True (duplicate ts, different field)
            (
                "300",
                self.TS_UPDATE,
                9002,
                1,
                False,
                True,
                self.TS_UPDATE,
                self.TS_REVISION,
                None,
                222,
            ),
        ]
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        update_status = [
            r
            for r in result.collect()
            if r["ts_transaction"] == self.TS_UPDATE and r["event_name"] == "ev_STATUS"
        ]
        assert len(update_status) == 1
        payload = json.loads(update_status[0]["payload"])
        # Should match rev 9001 (mod_status=True), not 9002 (mod_status=False)
        assert payload["rev"] == 9001
        assert payload["aud_user_id"] == 111

    def test_max_rev_tiebreaker_picks_highest_rev_for_same_mod_flag(
        self, spark_session
    ):
        # Two AUD rows at same ts with mod_status=True on both: should pick MAX(rev)
        cdc_data = [
            ("400", "Ativo", 2500.0, "c", self.TS_CREATE),
            ("400", "Finalizado", 2500.0, "u", self.TS_UPDATE),
        ]
        aud_data = [
            # Both have status_MOD=True; tiebreaker should pick rev 9002
            (
                "400",
                self.TS_UPDATE,
                9001,
                1,
                True,
                False,
                self.TS_UPDATE,
                self.TS_REVISION,
                None,
                111,
            ),
            (
                "400",
                self.TS_UPDATE,
                9002,
                1,
                True,
                False,
                self.TS_UPDATE,
                self.TS_REVISION,
                None,
                222,
            ),
        ]
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        update_status = [
            r
            for r in result.collect()
            if r["ts_transaction"] == self.TS_UPDATE and r["event_name"] == "ev_STATUS"
        ]
        assert len(update_status) == 1
        payload = json.loads(update_status[0]["payload"])
        assert payload["rev"] == 9002

    def test_insert_event_joins_aud_without_mod_flag_filter(self, spark_session):
        # On insert (op_cdc='c'), mod flags are never set by Envers.
        # The join should use rev_type=0 path, ignoring mod_status.
        cdc_data = [
            ("500", "Ativo", 2500.0, "c", self.TS_CREATE),
        ]
        aud_data = [
            # rEVTYPE=0 (insert revision); mod flags all False as expected
            (
                "500",
                self.TS_CREATE,
                8000,
                0,
                False,
                False,
                self.TS_CREATE,
                self.TS_REVISION,
                None,
                99,
            ),
        ]
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        create_rows = [
            r
            for r in result.collect()
            if r["ts_transaction"] == self.TS_CREATE and r["event_name"] == "ev_STATUS"
        ]
        assert len(create_rows) == 1
        assert create_rows[0]["payload"] is not None
        payload = json.loads(create_rows[0]["payload"])
        assert payload["op_cdc"] == "c"
        assert payload["rev"] == 8000
        assert payload["rev_type"] == 0

    def test_delete_event_payload_contains_op_cdc_d(self, spark_session):
        # Delete events (op_cdc='d') must have a non-null payload with op_cdc='d'
        # even when no AUD match is found (rev_type=2 is absent for soft-delete contracts).
        cdc_data = [
            ("600", "Ativo", 3000.0, "c", self.TS_CREATE),
            ("600", "Ativo", 3000.0, "d", self.TS_UPDATE),
        ]
        aud_data = []  # no AUD match for delete
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        delete_rows = [
            r for r in result.collect() if r["ts_transaction"] == self.TS_UPDATE
        ]
        assert len(delete_rows) == 2  # one per tracked column
        for row in delete_rows:
            assert row["payload"] is not None
            payload = json.loads(row["payload"])
            assert payload["op_cdc"] == "d"
            assert payload["payload_version"] == 1

    def test_snapshot_read_payload_is_always_null(self, spark_session):
        # op_cdc='r' rows must never receive AUD enrichment
        cdc_data = [
            ("700", "Ativo", 1800.0, "r", self.TS_CREATE),
        ]
        aud_data = [
            (
                "700",
                self.TS_CREATE,
                7000,
                0,
                False,
                False,
                self.TS_CREATE,
                self.TS_REVISION,
                None,
                55,
            ),
        ]
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        for row in result.collect():
            assert row["payload"] is None, (
                f"Snapshot read row should never have payload; got {row['payload']}"
            )

    def test_aud_disabled_keeps_payload_null(self, spark_session):
        cdc_data = [
            ("800", "Ativo", 2500.0, "c", self.TS_CREATE),
        ]
        aud_data = [
            (
                "800",
                self.TS_CREATE,
                8888,
                0,
                False,
                False,
                self.TS_CREATE,
                self.TS_REVISION,
                None,
                42,
            ),
        ]
        cdc_df = spark_session.createDataFrame(cdc_data, TRANSACTIONAL_SCHEMA)
        aud_df = spark_session.createDataFrame(aud_data, AUD_SCHEMA)
        disabled_config = {**AUD_CONFIG, "enabled": False}
        result = HistoryBuilder.build_history_for_columns(
            cdc_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=AUD_EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
            aud_df=aud_df,
            aud_config=disabled_config,
        )
        for row in result.collect():
            assert row["payload"] is None

    def test_unmapped_event_keeps_payload_null(self, spark_session):
        # paganteCondominio has no aud_mod_col -- must always keep payload=NULL
        schema_extra = StructType(
            [
                StructField("id", StringType(), True),
                StructField("status", StringType(), True),
                StructField("condo_payer", StringType(), True),
                StructField("op_cdc", StringType(), True),
                StructField("ts_database_transaction", TimestampType(), True),
            ]
        )
        event_configs_mixed = [
            {
                "tracked_col": "status",
                "event_name": "ev_STATUS",
                "aud_mod_col": "status_MOD",
            },
            {"tracked_col": "condo_payer", "event_name": "ev_CONDO"},  # no aud_mod_col
        ]
        cdc_df = spark_session.createDataFrame(
            [("900", "Ativo", "QuintoAndar", "c", self.TS_CREATE)], schema_extra
        )
        aud_sch = StructType(
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
        aud_df = spark_session.createDataFrame(
            [
                (
                    "900",
                    self.TS_CREATE,
                    1111,
                    0,
                    False,
                    self.TS_CREATE,
                    self.TS_REVISION,
                    None,
                    77,
                )
            ],
            aud_sch,
        )
        result = HistoryBuilder.build_history_for_columns(
            cdc_df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs_mixed,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
            aud_df=aud_df,
            aud_config=AUD_CONFIG,
        )
        rows = {r["event_name"]: r for r in result.collect()}
        assert rows["ev_CONDO"]["payload"] is None

    def test_payload_revision_reason_included_when_present(self, spark_session):
        cdc_data = [("1000", "Ativo", 2500.0, "c", self.TS_CREATE)]
        aud_data = [
            (
                "1000",
                self.TS_CREATE,
                5555,
                0,
                False,
                False,
                self.TS_CREATE,  # ts_cdc_transaction
                self.TS_REVISION,
                "Admin correction",
                888,
            )
        ]
        result = _build_with_aud(spark_session, cdc_data, aud_data)
        status_row = next(r for r in result.collect() if r["event_name"] == "ev_STATUS")
        payload = json.loads(status_row["payload"])
        assert payload["revision_reason"] == "Admin correction"


# ---------------------------------------------------------------------------
# Multi-AUD-source enrichment tests
# ---------------------------------------------------------------------------

# Second AUD source mirroring imovellistingrelation_aud's shape: different
# entity-id join column (imovelId, not id) and different revision-type column
# casing (REVTYPE, not rEVTYPE).
HLR_AUD_SCHEMA = StructType(
    [
        StructField("imovelId", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
        StructField("REV", LongType(), True),
        StructField("REVTYPE", IntegerType(), True),
        StructField("valorAluguel_MOD", BooleanType(), True),
        StructField("ts_cdc_transaction", TimestampType(), True),
        StructField("ts_revision", TimestampType(), True),
        StructField("revision_reason", StringType(), True),
        StructField("aud_user_id", LongType(), True),
    ]
)

MULTI_AUD_CONFIGS = [
    {
        "name": "imovel",
        "aud_id_col": "id",
        "revision_pk_col": "REV",
        "revision_type_col": "rEVTYPE",
        "enabled": True,
    },
    {
        "name": "hlr",
        "aud_id_col": "imovelId",
        "revision_pk_col": "REV",
        "revision_type_col": "REVTYPE",
        "enabled": True,
    },
]

MULTI_AUD_EVENT_CONFIGS = [
    {
        "tracked_col": "status",
        "event_name": "ev_STATUS",
        "aud_mod_col": "status_MOD",
        "aud_source": "imovel",
    },
    {
        "tracked_col": "rent",
        "event_name": "ev_RENT_VALUE",
        "aud_mod_col": "valorAluguel_MOD",
        "aud_source": "hlr",
    },
]


class TestHistoryBuilderMultiAudSource:
    """Enrichment from multiple named AUD sources via aud_dfs/aud_configs."""

    TS_CREATE = datetime(2026, 1, 10, 8, 0, 0)
    TS_UPDATE = datetime(2026, 1, 11, 9, 0, 0)
    TS_REVISION = datetime(2026, 1, 11, 9, 0, 1)

    def _build(
        self,
        spark_session,
        cdc_data,
        imovel_aud_data,
        hlr_aud_data,
        event_configs=None,
        aud_configs=None,
        aud_dfs=None,
    ):
        cdc_df = spark_session.createDataFrame(cdc_data, TRANSACTIONAL_SCHEMA)
        if aud_dfs is None:
            aud_dfs = {
                "imovel": spark_session.createDataFrame(imovel_aud_data, AUD_SCHEMA),
                "hlr": spark_session.createDataFrame(hlr_aud_data, HLR_AUD_SCHEMA),
            }
        return HistoryBuilder.build_history_for_columns(
            cdc_df,
            entity_name="house",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs or MULTI_AUD_EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
            aud_dfs=aud_dfs,
            aud_configs=aud_configs or MULTI_AUD_CONFIGS,
        )

    def _update_rows(self, result):
        return {
            r["event_name"]: r
            for r in result.collect()
            if r["ts_transaction"] == self.TS_UPDATE
        }

    def test_each_source_enriches_its_own_columns(self, spark_session):
        cdc_data = [
            ("100", "Ativo", 2500.0, "c", self.TS_CREATE),
            ("100", "Finalizado", 3000.0, "u", self.TS_UPDATE),
        ]
        imovel_aud_data = [
            (
                "100",
                self.TS_UPDATE,
                9001,
                1,
                True,  # status_MOD
                False,  # valorAluguel_MOD
                self.TS_UPDATE,
                self.TS_REVISION,
                "imovel reason",
                111,
            ),
        ]
        hlr_aud_data = [
            (
                "100",  # imovelId (different join column)
                self.TS_UPDATE,
                7001,
                1,  # REVTYPE (different casing)
                True,  # valorAluguel_MOD
                self.TS_UPDATE,
                self.TS_REVISION,
                "hlr reason",
                222,
            ),
        ]

        result = self._build(spark_session, cdc_data, imovel_aud_data, hlr_aud_data)
        rows = self._update_rows(result)

        status_payload = json.loads(rows["ev_STATUS"]["payload"])
        assert status_payload["rev"] == 9001
        assert status_payload["revision_reason"] == "imovel reason"
        assert status_payload["aud_user_id"] == 111

        rent_payload = json.loads(rows["ev_RENT_VALUE"]["payload"])
        assert rent_payload["rev"] == 7001
        assert rent_payload["revision_reason"] == "hlr reason"
        assert rent_payload["aud_user_id"] == 222

    def test_insert_path_uses_each_sources_revision_type_column(self, spark_session):
        # rev_type=0 rows must be recognized through each source's own
        # revision_type_col (rEVTYPE vs REVTYPE).
        cdc_data = [("100", "Ativo", 2500.0, "c", self.TS_CREATE)]
        imovel_aud_data = [
            (
                "100",
                self.TS_CREATE,
                5001,
                0,  # rEVTYPE=0 (insert revision)
                False,
                False,
                self.TS_CREATE,
                self.TS_REVISION,
                None,
                111,
            ),
        ]
        hlr_aud_data = [
            (
                "100",
                self.TS_CREATE,
                4001,
                0,  # REVTYPE=0 (insert revision)
                False,
                self.TS_CREATE,
                self.TS_REVISION,
                None,
                222,
            ),
        ]

        result = self._build(spark_session, cdc_data, imovel_aud_data, hlr_aud_data)
        rows = {r["event_name"]: r for r in result.collect()}

        assert json.loads(rows["ev_STATUS"]["payload"])["rev"] == 5001
        assert json.loads(rows["ev_RENT_VALUE"]["payload"])["rev"] == 4001

    def test_raises_when_both_singular_and_plural_given(self, spark_session):
        cdc_df = spark_session.createDataFrame(
            [("100", "Ativo", 2500.0, "c", self.TS_CREATE)], TRANSACTIONAL_SCHEMA
        )
        aud_df = spark_session.createDataFrame([], AUD_SCHEMA)

        with pytest.raises(ValueError, match="not both"):
            HistoryBuilder.build_history_for_columns(
                cdc_df,
                entity_name="house",
                id_col="id",
                ts_col="ts_database_transaction",
                op_col="op_cdc",
                event_configs=MULTI_AUD_EVENT_CONFIGS,
                aud_df=aud_df,
                aud_config=AUD_CONFIG,
                aud_dfs={"imovel": aud_df},
                aud_configs=MULTI_AUD_CONFIGS,
            )

    def test_raises_when_aud_mod_col_missing_aud_source_with_multiple_sources(
        self, spark_session
    ):
        event_configs = [
            {
                "tracked_col": "status",
                "event_name": "ev_STATUS",
                "aud_mod_col": "status_MOD",
                # no aud_source, but two sources configured
            },
        ]

        with pytest.raises(ValueError, match="aud_source is required"):
            self._build(spark_session, [], [], [], event_configs=event_configs)

    def test_raises_on_unknown_aud_source(self, spark_session):
        event_configs = [
            {
                "tracked_col": "status",
                "event_name": "ev_STATUS",
                "aud_mod_col": "status_MOD",
                "aud_source": "typo_source",
            },
        ]

        with pytest.raises(ValueError, match="unknown aud_source"):
            self._build(spark_session, [], [], [], event_configs=event_configs)

    def test_sole_source_is_default_when_aud_source_omitted(self, spark_session):
        cdc_data = [
            ("100", "Ativo", 2500.0, "c", self.TS_CREATE),
            ("100", "Finalizado", 2500.0, "u", self.TS_UPDATE),
        ]
        imovel_aud_data = [
            (
                "100",
                self.TS_UPDATE,
                9001,
                1,
                True,
                False,
                self.TS_UPDATE,
                self.TS_REVISION,
                None,
                111,
            ),
        ]
        event_configs = [
            {
                "tracked_col": "status",
                "event_name": "ev_STATUS",
                "aud_mod_col": "status_MOD",
                # no aud_source: defaults to the sole configured source
            },
        ]
        aud_configs = [MULTI_AUD_CONFIGS[0]]
        aud_dfs = {"imovel": spark_session.createDataFrame(imovel_aud_data, AUD_SCHEMA)}

        result = self._build(
            spark_session,
            cdc_data,
            imovel_aud_data,
            [],
            event_configs=event_configs,
            aud_configs=aud_configs,
            aud_dfs=aud_dfs,
        )
        rows = self._update_rows(result)

        assert json.loads(rows["ev_STATUS"]["payload"])["rev"] == 9001

    def test_disabled_source_leaves_its_events_unenriched(self, spark_session):
        cdc_data = [
            ("100", "Ativo", 2500.0, "c", self.TS_CREATE),
            ("100", "Finalizado", 3000.0, "u", self.TS_UPDATE),
        ]
        imovel_aud_data = [
            (
                "100",
                self.TS_UPDATE,
                9001,
                1,
                True,
                False,
                self.TS_UPDATE,
                self.TS_REVISION,
                None,
                111,
            ),
        ]
        aud_configs = [
            MULTI_AUD_CONFIGS[0],
            {**MULTI_AUD_CONFIGS[1], "enabled": False},
        ]
        # Disabled source has no loaded DataFrame (mirrors
        # HistoricalHelper.load_aud_revision_datasets output).
        aud_dfs = {"imovel": spark_session.createDataFrame(imovel_aud_data, AUD_SCHEMA)}

        result = self._build(
            spark_session,
            cdc_data,
            imovel_aud_data,
            [],
            aud_configs=aud_configs,
            aud_dfs=aud_dfs,
        )
        rows = self._update_rows(result)

        assert rows["ev_STATUS"]["payload"] is not None
        assert rows["ev_RENT_VALUE"]["payload"] is None


class TestHistoryBuilderCanonicalization:
    """Tests for the canonicalization pipeline (Steps 1, 2, 5)."""

    SNAPSHOT_TS = datetime(2025, 5, 12, 0, 0, 0)

    def _build(self, df, tie_breakers=None):
        return HistoryBuilder.build_history_for_columns(
            df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=EVENT_CONFIGS,
            event_type="cdc",
            event_origin=SOURCE_TABLE,
            canonicalize_tie_breaker_columns=tie_breakers,
        )

    def test_exact_dedupe_drops_partition_artifact_pairs(self, spark_session):
        # arrange -- identical business payload, differing only in partition
        # columns and binlog position (a partition-artifact pair).
        upd = datetime(2025, 5, 12, 0, 0, 0)
        cdc = datetime(2025, 5, 12, 1, 0, 0)
        data = [
            (
                "800",
                "Ativo",
                2500.0,
                "r",
                self.SNAPSHOT_TS,
                7,
                upd,
                cdc,
                10,
                "tx",
                None,
                None,
                None,
            ),
            (
                "800",
                "Ativo",
                2500.0,
                "r",
                self.SNAPSHOT_TS,
                7,
                upd,
                cdc,
                20,
                "tx",
                2025,
                5,
                12,
            ),
        ]
        df = spark_session.createDataFrame(data, CANON_SCHEMA)
        result = self._build(df)
        rows = result.collect()

        # assert -- one event per tracked column, no duplicate id_event
        assert len(rows) == 2
        assert {r["event_name"] for r in rows} == {"ev_STATUS", "ev_RENT_VALUE"}
        assert len({r["id_event"] for r in rows}) == 2

    def test_canonicalize_picks_max_version_at_same_ts(self, spark_session):
        # arrange -- replay of 3 revisions at one snapshot instant, versions 5/6/7
        upd = datetime(2025, 5, 12, 0, 0, 0)
        cdc = datetime(2025, 5, 12, 1, 0, 0)
        data = [
            (
                "801",
                "V5",
                100.0,
                "r",
                self.SNAPSHOT_TS,
                5,
                upd,
                cdc,
                1,
                "tx",
                2025,
                5,
                12,
            ),
            (
                "801",
                "V7",
                300.0,
                "r",
                self.SNAPSHOT_TS,
                7,
                upd,
                cdc,
                1,
                "tx",
                2025,
                5,
                12,
            ),
            (
                "801",
                "V6",
                200.0,
                "r",
                self.SNAPSHOT_TS,
                6,
                upd,
                cdc,
                1,
                "tx",
                2025,
                5,
                12,
            ),
        ]
        df = spark_session.createDataFrame(data, CANON_SCHEMA)
        result = self._build(df)
        rows = result.collect()

        # assert -- only the highest-version revision survives
        status_rows = [r for r in rows if r["event_name"] == "ev_STATUS"]
        rent_rows = [r for r in rows if r["event_name"] == "ev_RENT_VALUE"]
        assert len(status_rows) == 1
        assert status_rows[0]["value"] == "V7"
        assert len(rent_rows) == 1
        assert rent_rows[0]["value"] == "300.0"

    def test_same_ts_different_values_collapse_to_one_event(self, spark_session):
        # arrange -- two rows at same ts, different value, version decides
        upd = datetime(2025, 5, 12, 0, 0, 0)
        cdc = datetime(2025, 5, 12, 1, 0, 0)
        data = [
            (
                "802",
                "Ativo",
                2500.0,
                "r",
                self.SNAPSHOT_TS,
                1,
                upd,
                cdc,
                1,
                "tx",
                2025,
                5,
                12,
            ),
            (
                "802",
                "Finalizado",
                2500.0,
                "r",
                self.SNAPSHOT_TS,
                2,
                upd,
                cdc,
                1,
                "tx",
                2025,
                5,
                12,
            ),
        ]
        df = spark_session.createDataFrame(data, CANON_SCHEMA)
        result = self._build(df)
        status_rows = [r for r in result.collect() if r["event_name"] == "ev_STATUS"]

        # assert -- exactly one status event (version 2 wins), unique id_event
        assert len(status_rows) == 1
        assert status_rows[0]["value"] == "Finalizado"

    def test_output_id_event_is_unique(self, spark_session):
        # arrange -- multi-entity snapshot replay with several rows per (id, ts)
        upd = datetime(2025, 5, 12, 0, 0, 0)
        cdc = datetime(2025, 5, 12, 1, 0, 0)
        data = [
            ("900", "A", 10.0, "r", self.SNAPSHOT_TS, v, upd, cdc, 1, "tx", 2025, 5, 12)
            for v in range(5)
        ] + [
            ("901", "B", 20.0, "r", self.SNAPSHOT_TS, v, upd, cdc, 1, "tx", 2025, 5, 12)
            for v in range(8)
        ]
        df = spark_session.createDataFrame(data, CANON_SCHEMA)
        result = self._build(df)
        rows = result.collect()

        # assert -- id_event is unique across the whole output
        id_events = [r["id_event"] for r in rows]
        assert len(id_events) == len(set(id_events))

    def test_custom_tie_breaker_columns(self, spark_session):
        # arrange -- two rows tied on version/updated_at; only binlog differs
        upd = datetime(2025, 5, 12, 0, 0, 0)
        cdc = datetime(2025, 5, 12, 1, 0, 0)
        data = [
            (
                "803",
                "low",
                1.0,
                "r",
                self.SNAPSHOT_TS,
                1,
                upd,
                cdc,
                100,
                "tx",
                2025,
                5,
                12,
            ),
            (
                "803",
                "high",
                2.0,
                "r",
                self.SNAPSHOT_TS,
                1,
                upd,
                cdc,
                200,
                "tx",
                2025,
                5,
                12,
            ),
        ]
        df = spark_session.createDataFrame(data, CANON_SCHEMA)
        # override: rank by binlog position only -> highest (200) wins
        result = self._build(df, tie_breakers=["cdc_binlog_position"])
        status_rows = [r for r in result.collect() if r["event_name"] == "ev_STATUS"]

        # assert
        assert len(status_rows) == 1
        assert status_rows[0]["value"] == "high"

    def test_missing_version_falls_back_to_cdc_columns(self, spark_session):
        # arrange -- imovel profile (no version/updated_at); ts_cdc_transaction
        # is the leading present tie-breaker.
        early_cdc = datetime(2025, 5, 12, 1, 0, 0)
        late_cdc = datetime(2025, 5, 12, 2, 0, 0)
        data = [
            ("804", "old", 1.0, "r", self.SNAPSHOT_TS, early_cdc, 1, "tx"),
            ("804", "new", 2.0, "r", self.SNAPSHOT_TS, late_cdc, 2, "tx"),
        ]
        df = spark_session.createDataFrame(data, IMOVEL_SCHEMA)
        result = self._build(df)
        status_rows = [r for r in result.collect() if r["event_name"] == "ev_STATUS"]

        # assert -- latest ts_cdc_transaction wins; one row per (id, ts)
        assert len(status_rows) == 1
        assert status_rows[0]["value"] == "new"


# ---------------------------------------------------------------------------
# value_precision: normalize tracked timestamps before change detection
# ---------------------------------------------------------------------------

TS_PRECISION_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("created_at", TimestampType(), True),
        StructField("op_cdc", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
    ]
)

# Mirrors the observed core_region.business_unit_history bug: an immutable
# created_at rendered at microsecond precision on streaming CDC rows and at
# millisecond precision on the snapshot (op_cdc='r') row.
MICROS_VALUE = datetime(2022, 7, 13, 19, 51, 35, 816026)
MILLIS_VALUE = datetime(2022, 7, 13, 19, 51, 35, 816000)


def _ts_precision_configs(value_precision=None):
    config = {
        "tracked_col": "created_at",
        "target_col": "ts_created",
        "target_type": "timestamp",
    }
    if value_precision is not None:
        config["value_precision"] = value_precision
    return [config]


class TestHistoryBuilderValuePrecision:
    """Tests for the opt-in ``value_precision`` timestamp normalization."""

    def _build(self, spark_session, data, value_precision=None):
        df = spark_session.createDataFrame(data, TS_PRECISION_SCHEMA)
        return HistoryBuilder.build_history_for_columns(
            df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=_ts_precision_configs(value_precision),
            event_type="cdc",
            event_origin=SOURCE_TABLE,
        )

    def test_millisecond_precision_collapses_micros_millis_to_one_event(
        self, spark_session
    ):
        # arrange -- create (micros), snapshot (millis), update (micros): the
        # value is immutable but its render flips precision across rows.
        data = [
            ("1", MICROS_VALUE, "c", datetime(2025, 5, 9, 17, 14, 25)),
            ("1", MILLIS_VALUE, "r", datetime(2025, 5, 12, 0, 0, 0)),
            ("1", MICROS_VALUE, "u", datetime(2025, 5, 29, 19, 21, 24)),
        ]
        result = self._build(spark_session, data, value_precision="millisecond")
        rows = [r for r in result.collect() if r["event_name"] == "ev_ts_created"]

        # assert -- normalized to millisecond, all three render equal -> one event
        assert len(rows) == 1
        assert rows[0]["value"] == "2022-07-13 19:51:35.816"

    def test_without_value_precision_micros_millis_flip_emits_multiple_events(
        self, spark_session
    ):
        # arrange -- same data, no normalization (documents the bug being fixed)
        data = [
            ("1", MICROS_VALUE, "c", datetime(2025, 5, 9, 17, 14, 25)),
            ("1", MILLIS_VALUE, "r", datetime(2025, 5, 12, 0, 0, 0)),
            ("1", MICROS_VALUE, "u", datetime(2025, 5, 29, 19, 21, 24)),
        ]
        result = self._build(spark_session, data, value_precision=None)
        rows = [r for r in result.collect() if r["event_name"] == "ev_ts_created"]

        # assert -- each precision flip is seen as a change -> three events
        assert len(rows) == 3

    def test_second_precision_truncates_subsecond_and_collapses(self, spark_session):
        # arrange -- two renders differing only below the second
        data = [
            ("2", MICROS_VALUE, "c", datetime(2025, 5, 9, 17, 14, 25)),
            ("2", MILLIS_VALUE, "u", datetime(2025, 5, 29, 19, 21, 24)),
        ]
        result = self._build(spark_session, data, value_precision="second")
        rows = [r for r in result.collect() if r["event_name"] == "ev_ts_created"]

        # assert -- truncated to the second, both render equal -> one event
        assert len(rows) == 1
        assert rows[0]["value"] == "2022-07-13 19:51:35"

    def test_genuine_value_change_still_emits_after_normalization(self, spark_session):
        # arrange -- a real change above the normalized precision must survive
        later = datetime(2023, 1, 1, 10, 0, 0, 500000)
        data = [
            ("3", MICROS_VALUE, "c", datetime(2025, 5, 9, 17, 14, 25)),
            ("3", later, "u", datetime(2025, 5, 29, 19, 21, 24)),
        ]
        result = self._build(spark_session, data, value_precision="millisecond")
        rows = [r for r in result.collect() if r["event_name"] == "ev_ts_created"]

        # assert -- distinct millisecond values -> two events
        assert len(rows) == 2

    def test_unsupported_value_precision_raises_value_error(self, spark_session):
        data = [("4", MICROS_VALUE, "c", datetime(2025, 5, 9, 17, 14, 25))]
        df = spark_session.createDataFrame(data, TS_PRECISION_SCHEMA)
        with pytest.raises(ValueError, match="unsupported value_precision"):
            HistoryBuilder.build_history_for_columns(
                df,
                entity_name="contract",
                id_col="id",
                ts_col="ts_database_transaction",
                op_col="op_cdc",
                event_configs=_ts_precision_configs(value_precision="nanosecond"),
                event_type="cdc",
                event_origin=SOURCE_TABLE,
            )
