"""Unit tests for CurrentStateBuilder."""

from datetime import datetime

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.core_models.helpers.current_state_builder import (
    CurrentStateBuilder,
)


@pytest.fixture(scope="session")
def spark():
    spark = (
        SparkSession.builder.appName("CurrentStateBuilderTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


HISTORY_SCHEMA = StructType(
    [
        StructField("id_event", StringType(), True),
        StructField("id_contract", StringType(), True),
        StructField("sk_contract", StringType(), True),
        StructField("event_name", StringType(), True),
        StructField("event_type", StringType(), True),
        StructField("value", StringType(), True),
        StructField("payload", StringType(), True),
        StructField("ts_transaction", TimestampType(), True),
        StructField("event_origin", StringType(), True),
        StructField("ts_load", TimestampType(), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)

COMPOSITE_HISTORY_SCHEMA = StructType(
    [
        StructField("id_event", StringType(), True),
        StructField("id_region", StringType(), True),
        StructField("id_business_unit", StringType(), True),
        StructField("sk_core_business_unit_region", StringType(), True),
        StructField("event_name", StringType(), True),
        StructField("event_type", StringType(), True),
        StructField("value", StringType(), True),
        StructField("payload", StringType(), True),
        StructField("ts_transaction", TimestampType(), True),
        StructField("event_origin", StringType(), True),
        StructField("ts_load", TimestampType(), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)

COMPOSITE_EVENT_CONFIGS = [
    {
        "tracked_col": "hub_name",
        "event_name": "ev_hub_name",
        "target_col": "hub_name",
        "target_type": "string",
    },
    {
        "tracked_col": "negotiation_type",
        "event_name": "ev_negotiation_type",
        "target_col": "negotiation_type",
        "target_type": "string",
    },
]

EVENT_CONFIGS = [
    {
        "tracked_col": "status",
        "event_name": "ev_STATUS",
        "target_col": "status",
        "target_type": "string",
    },
    {
        "tracked_col": "valorAluguel",
        "event_name": "ev_RENT_VALUE",
        "target_col": "rent",
        "target_type": "double",
    },
    {
        "tracked_col": "iptu_valor",
        "event_name": "ev_IPTU_VALUE",
        "target_col": "iptu",
        "target_type": "double",
    },
]


@pytest.fixture
def sample_history(spark):
    data = [
        (
            "e1",
            "100",
            "sk1",
            "ev_STATUS",
            "cdc",
            "Ativo",
            None,
            datetime(2026, 1, 10, 8, 0),
            "t.contrato",
            datetime(2026, 1, 10, 8, 1),
            2026,
            1,
            10,
        ),
        (
            "e2",
            "100",
            "sk1",
            "ev_RENT_VALUE",
            "cdc",
            "2500.0",
            None,
            datetime(2026, 1, 10, 8, 0),
            "t.contrato",
            datetime(2026, 1, 10, 8, 1),
            2026,
            1,
            10,
        ),
        (
            "e3",
            "100",
            "sk1",
            "ev_IPTU_VALUE",
            "cdc",
            "100.0",
            None,
            datetime(2026, 1, 10, 8, 0),
            "t.contrato",
            datetime(2026, 1, 10, 8, 1),
            2026,
            1,
            10,
        ),
        (
            "e4",
            "100",
            "sk1",
            "ev_STATUS",
            "cdc",
            "Finalizado",
            None,
            datetime(2026, 1, 15, 9, 0),
            "t.contrato",
            datetime(2026, 1, 15, 9, 1),
            2026,
            1,
            15,
        ),
        (
            "e5",
            "200",
            "sk2",
            "ev_STATUS",
            "cdc",
            "Ativo",
            None,
            datetime(2026, 1, 12, 10, 0),
            "t.contrato",
            datetime(2026, 1, 12, 10, 1),
            2026,
            1,
            12,
        ),
        (
            "e6",
            "200",
            "sk2",
            "ev_RENT_VALUE",
            "cdc",
            "3000.0",
            None,
            datetime(2026, 1, 12, 10, 0),
            "t.contrato",
            datetime(2026, 1, 12, 10, 1),
            2026,
            1,
            12,
        ),
    ]
    return spark.createDataFrame(data, HISTORY_SCHEMA)


class TestCurrentStateBuilder:
    def test_builds_wide_dataframe_with_expected_columns(self, spark, sample_history):
        # act
        result = CurrentStateBuilder.build_current_state(
            sample_history, "id_contract", EVENT_CONFIGS
        )
        # assert
        assert "id_contract" in result.columns
        assert "status" in result.columns
        assert "rent" in result.columns
        assert "iptu" in result.columns

    def test_latest_value_wins_when_multiple_events_exist(self, spark, sample_history):
        # act
        result = CurrentStateBuilder.build_current_state(
            sample_history, "id_contract", EVENT_CONFIGS
        )
        # assert — contract 100 status updated Ativo→Finalizado on Jan 15
        row = result.filter("id_contract = '100'").collect()[0]
        assert row["status"] == "Finalizado"

    def test_casts_string_values_to_target_types(self, spark, sample_history):
        # act
        result = CurrentStateBuilder.build_current_state(
            sample_history, "id_contract", EVENT_CONFIGS
        )
        # assert
        row = result.filter("id_contract = '100'").collect()[0]
        assert isinstance(row["rent"], float)
        assert row["rent"] == 2500.0
        assert row["iptu"] == 100.0

    def test_filters_entities_by_date_range(self, spark, sample_history):
        # act — only Jan 12–14: contract 200 created, contract 100 unchanged
        result = CurrentStateBuilder.build_current_state(
            sample_history,
            "id_contract",
            EVENT_CONFIGS,
            load_start_date="2026-01-12",
            load_end_date="2026-01-14",
        )
        # assert — only contract 200
        assert result.count() == 1
        row = result.collect()[0]
        assert row["id_contract"] == "200"
        assert row["status"] == "Ativo"
        assert row["rent"] == 3000.0

    def test_returns_all_entities_when_no_date_range(self, spark, sample_history):
        # act
        result = CurrentStateBuilder.build_current_state(
            sample_history, "id_contract", EVENT_CONFIGS
        )
        # assert
        assert result.count() == 2

    def test_empty_history_returns_empty_dataframe(self, spark):
        # arrange
        empty = spark.createDataFrame([], HISTORY_SCHEMA)
        # act
        result = CurrentStateBuilder.build_current_state(
            empty, "id_contract", EVENT_CONFIGS
        )
        # assert
        assert result.count() == 0

    def test_missing_event_for_entity_produces_null_column(self, spark, sample_history):
        # contract 200 has ev_STATUS and ev_RENT_VALUE but no ev_IPTU_VALUE
        result = CurrentStateBuilder.build_current_state(
            sample_history, "id_contract", EVENT_CONFIGS
        )
        row = result.filter("id_contract = '200'").collect()[0]
        assert row["iptu"] is None

    def test_validates_missing_event_config_keys(self, spark, sample_history):
        # arrange — missing target_col and target_type
        bad_configs = [{"event_name": "ev_STATUS", "tracked_col": "status"}]
        # act / assert
        with pytest.raises(ValueError, match="missing"):
            CurrentStateBuilder.build_current_state(
                sample_history, "id_contract", bad_configs
            )

    def test_validates_duplicate_target_col(self, spark, sample_history):
        # arrange — two configs map to the same output column
        bad_configs = [
            {"event_name": "ev_A", "target_col": "status", "target_type": "string"},
            {"event_name": "ev_B", "target_col": "status", "target_type": "string"},
        ]
        # act / assert
        with pytest.raises(ValueError, match="duplicate target_col"):
            CurrentStateBuilder.build_current_state(
                sample_history, "id_contract", bad_configs
            )

    def test_validates_duplicate_event_name(self, spark, sample_history):
        # arrange — two configs resolve to the same event_name
        bad_configs = [
            {
                "event_name": "ev_STATUS",
                "target_col": "status",
                "target_type": "string",
            },
            {"event_name": "ev_STATUS", "target_col": "state", "target_type": "string"},
        ]
        # act / assert
        with pytest.raises(ValueError, match="duplicate event_name"):
            CurrentStateBuilder.build_current_state(
                sample_history, "id_contract", bad_configs
            )

    def test_validates_duplicate_id_cols(self, spark, sample_history):
        # arrange / act / assert — duplicate grain columns are rejected
        with pytest.raises(ValueError, match="duplicate columns"):
            CurrentStateBuilder.build_current_state(
                sample_history, ["id_contract", "id_contract"], EVENT_CONFIGS
            )

    def test_event_name_derived_from_target_col(self, spark):
        configs = [{"target_col": "status", "target_type": "string"}]
        data = [
            (
                "e1",
                "100",
                "sk1",
                "ev_status",
                "cdc",
                "Ativo",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.contrato",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
        ]
        history = spark.createDataFrame(data, HISTORY_SCHEMA)
        result = CurrentStateBuilder.build_current_state(
            history, "id_contract", configs
        )
        assert result.collect()[0]["status"] == "Ativo"

    def test_explicit_event_name_maps_to_target_col(self, spark):
        configs = [
            {
                "event_name": "ev_STATUS",
                "target_col": "contract_status",
                "target_type": "string",
            }
        ]
        data = [
            (
                "e1",
                "100",
                "sk1",
                "ev_STATUS",
                "cdc",
                "Signed",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.contrato",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
        ]
        history = spark.createDataFrame(data, HISTORY_SCHEMA)
        result = CurrentStateBuilder.build_current_state(
            history, "id_contract", configs
        )
        row = result.collect()[0]
        assert row["contract_status"] == "Signed"

    def test_validates_unresolvable_event_name(self, spark, sample_history):
        bad_configs = [{"target_col": "", "target_type": "string", "event_name": ""}]
        with pytest.raises(ValueError, match="event_name' or 'target_col"):
            CurrentStateBuilder.build_current_state(
                sample_history, "id_contract", bad_configs
            )

    def test_null_value_in_history_produces_null_in_current_state(self, spark):
        # arrange
        data = [
            (
                "e1",
                "100",
                "sk1",
                "ev_STATUS",
                "cdc",
                None,
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.contrato",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
            (
                "e2",
                "100",
                "sk1",
                "ev_RENT_VALUE",
                "cdc",
                "1000.0",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.contrato",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
        ]
        history = spark.createDataFrame(data, HISTORY_SCHEMA)
        # act
        result = CurrentStateBuilder.build_current_state(
            history, "id_contract", EVENT_CONFIGS
        )
        # assert
        row = result.collect()[0]
        assert row["status"] is None
        assert row["rent"] == 1000.0

    @pytest.mark.parametrize(
        "target_type, raw_value, expected",
        [
            ("boolean", "true", True),
            ("boolean", "false", False),
            ("date", "2026-01-15", "2026-01-15"),
            ("int", "42", 42),
        ],
    )
    def test_type_casting_variants(self, spark, target_type, raw_value, expected):
        configs = [
            {
                "tracked_col": "col",
                "event_name": "ev_COL",
                "target_col": "col_out",
                "target_type": target_type,
            }
        ]
        data = [
            (
                "e1",
                "1",
                "sk1",
                "ev_COL",
                "cdc",
                raw_value,
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.tbl",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
        ]
        history = spark.createDataFrame(data, HISTORY_SCHEMA)
        result = CurrentStateBuilder.build_current_state(
            history, "id_contract", configs
        )
        row = result.collect()[0]
        actual = row["col_out"]
        if target_type == "date":
            assert str(actual) == expected
        else:
            assert actual == expected

    def test_builds_composite_grain_one_row_per_pair(self, spark):
        # arrange — two region<>business_unit pairs, each with its own events
        data = [
            (
                "e1",
                "R1",
                "B1",
                "sk_r1_b1",
                "ev_hub_name",
                "cdc",
                "Hub Alpha",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.business_unit_region",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
            (
                "e2",
                "R1",
                "B1",
                "sk_r1_b1",
                "ev_negotiation_type",
                "cdc",
                "RENT",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.business_unit_region",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
            # same pair (R1,B1): hub_name updated later -> latest wins
            (
                "e3",
                "R1",
                "B1",
                "sk_r1_b1",
                "ev_hub_name",
                "cdc",
                "Hub Alpha Renamed",
                None,
                datetime(2026, 1, 20, 8, 0),
                "t.business_unit_region",
                datetime(2026, 1, 20, 8, 1),
                2026,
                1,
                20,
            ),
            # different pair sharing the same business_unit B1 but region R2
            (
                "e4",
                "R2",
                "B1",
                "sk_r2_b1",
                "ev_hub_name",
                "cdc",
                "Hub Beta",
                None,
                datetime(2026, 1, 12, 8, 0),
                "t.business_unit_region",
                datetime(2026, 1, 12, 8, 1),
                2026,
                1,
                12,
            ),
        ]
        history = spark.createDataFrame(data, COMPOSITE_HISTORY_SCHEMA)
        # act
        result = CurrentStateBuilder.build_current_state(
            history, ["id_region", "id_business_unit"], COMPOSITE_EVENT_CONFIGS
        )
        # assert — one row per pair, latest value per pair
        assert "id_region" in result.columns
        assert "id_business_unit" in result.columns
        assert result.count() == 2
        r1 = result.filter("id_region = 'R1' and id_business_unit = 'B1'").collect()[0]
        assert r1["hub_name"] == "Hub Alpha Renamed"
        assert r1["negotiation_type"] == "RENT"
        r2 = result.filter("id_region = 'R2' and id_business_unit = 'B1'").collect()[0]
        assert r2["hub_name"] == "Hub Beta"
        assert r2["negotiation_type"] is None

    def test_latest_value_tie_breaks_deterministically_on_value(self, spark):
        # arrange — residual same-ts duplicates that can survive a history
        # first-run direct-write (no canonicalization): same entity, same
        # event_name, same ts_transaction, different value. id_event cannot
        # disambiguate (it is a hash of grain+event+ts), so the content-bearing
        # ``value desc`` tie-break must decide deterministically.
        configs = [{"target_col": "status", "target_type": "string"}]
        data = [
            (
                "e1",
                "100",
                "sk1",
                "ev_status",
                "cdc",
                "A",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.contrato",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
            (
                "e2",
                "100",
                "sk1",
                "ev_status",
                "cdc",
                "B",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.contrato",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
        ]
        history = spark.createDataFrame(data, HISTORY_SCHEMA)
        # act — run twice to confirm stability
        first = CurrentStateBuilder.build_current_state(
            history, "id_contract", configs
        ).collect()[0]["status"]
        second = CurrentStateBuilder.build_current_state(
            history, "id_contract", configs
        ).collect()[0]["status"]
        # assert — value 'B' > 'A' wins, deterministically across runs
        assert first == "B"
        assert second == "B"

    def test_latest_value_prefers_max_ts_over_value_tiebreak(self, spark):
        # arrange — the value tie-break must only apply within the same
        # ts_transaction; a later ts with a lexically-smaller value still wins.
        configs = [{"target_col": "status", "target_type": "string"}]
        data = [
            (
                "e1",
                "100",
                "sk1",
                "ev_status",
                "cdc",
                "Z_old",
                None,
                datetime(2026, 1, 10, 8, 0),
                "t.contrato",
                datetime(2026, 1, 10, 8, 1),
                2026,
                1,
                10,
            ),
            (
                "e2",
                "100",
                "sk1",
                "ev_status",
                "cdc",
                "A_new",
                None,
                datetime(2026, 1, 20, 8, 0),
                "t.contrato",
                datetime(2026, 1, 20, 8, 1),
                2026,
                1,
                20,
            ),
        ]
        history = spark.createDataFrame(data, HISTORY_SCHEMA)
        # act
        row = CurrentStateBuilder.build_current_state(
            history, "id_contract", configs
        ).collect()[0]
        # assert — latest ts wins even though 'A_new' < 'Z_old' lexically
        assert row["status"] == "A_new"

    def test_validate_output_raises_on_null_key(self, spark):
        # arrange — output row carrying a null grain key
        df = spark.createDataFrame(
            [("100", "Ativo"), (None, "Finalizado")],
            StructType(
                [
                    StructField("id_contract", StringType(), True),
                    StructField("status", StringType(), True),
                ]
            ),
        )
        # act / assert
        with pytest.raises(ValueError, match="null grain"):
            CurrentStateBuilder._validate_output(df, ["id_contract"])

    def test_validate_output_raises_on_duplicate_grain(self, spark):
        # arrange — two rows sharing the same composite grain
        df = spark.createDataFrame(
            [("R1", "B1", "x"), ("R1", "B1", "y")],
            StructType(
                [
                    StructField("id_region", StringType(), True),
                    StructField("id_business_unit", StringType(), True),
                    StructField("hub_name", StringType(), True),
                ]
            ),
        )
        # act / assert
        with pytest.raises(ValueError, match="not unique"):
            CurrentStateBuilder._validate_output(df, ["id_region", "id_business_unit"])

    def test_validate_output_passes_on_valid_grain(self, spark):
        # arrange — unique, non-null grain
        df = spark.createDataFrame(
            [("100", "Ativo"), ("200", "Finalizado")],
            StructType(
                [
                    StructField("id_contract", StringType(), True),
                    StructField("status", StringType(), True),
                ]
            ),
        )
        # act / assert — no raise
        CurrentStateBuilder._validate_output(df, ["id_contract"])

    def test_require_non_empty_raises_on_empty_output(self, spark):
        # arrange
        df = spark.createDataFrame(
            [],
            StructType(
                [
                    StructField("id_contract", StringType(), True),
                    StructField("status", StringType(), True),
                ]
            ),
        )
        # act / assert
        with pytest.raises(ValueError, match="empty"):
            CurrentStateBuilder._validate_output(
                df, ["id_contract"], require_non_empty=True
            )

    def test_validate_false_skips_guard_on_empty_history(self, spark):
        # arrange — empty history; validate disabled must not raise and yield empty
        empty = spark.createDataFrame([], HISTORY_SCHEMA)
        # act
        result = CurrentStateBuilder.build_current_state(
            empty, "id_contract", EVENT_CONFIGS, validate=False
        )
        # assert
        assert result.count() == 0

    def test_require_non_empty_enforced_even_when_validate_false(self, spark):
        # arrange — empty history; require_non_empty must fire independently of validate
        empty = spark.createDataFrame([], HISTORY_SCHEMA)
        # act / assert
        with pytest.raises(ValueError, match="empty"):
            CurrentStateBuilder.build_current_state(
                empty,
                "id_contract",
                EVENT_CONFIGS,
                validate=False,
                require_non_empty=True,
            )
