"""Unit tests for HistoryBuilder."""

import pytest
from datetime import datetime

from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    DoubleType,
    BooleanType,
    IntegerType,
)

from bietlejuice.base.core_models.helpers.history_builder import HistoryBuilder


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
