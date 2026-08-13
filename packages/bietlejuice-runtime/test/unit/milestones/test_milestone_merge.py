"""Unit tests for generic milestone grain/merge contract."""

from __future__ import annotations

from datetime import datetime

import pytest
from pyspark.sql import functions as F
from pyspark.sql.types import (
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.milestones.contract import (
    MilestoneTableSpec,
    build_scan_predicate,
)
from bietlejuice.milestones.merge import aggregate_events, prepare_merge_batch
from bietlejuice.milestones.orchestrator import empty_dim_df
from bietlejuice.milestones.registry import (
    load_milestones_from_metadata_yaml,
    resolve_milestones_for_run,
    validate_milestones_registry,
)


def _ts(year: int, month: int, day: int, hour: int = 0) -> datetime:
    return datetime(year, month, day, hour, 0, 0)


@pytest.fixture
def agents_spec() -> MilestoneTableSpec:
    return MilestoneTableSpec.from_merge_on(
        ["sk_user", "milestone_type"], sticky_columns=["id_agent"]
    )


@pytest.fixture
def house_spec() -> MilestoneTableSpec:
    return MilestoneTableSpec.from_merge_on(
        ["id_house", "milestone_type"], sticky_columns=[]
    )


def test_spec_rejects_missing_milestone_type():
    with pytest.raises(ValueError, match="milestone_type"):
        MilestoneTableSpec.from_merge_on(["sk_user"])


def test_spec_rejects_empty_entity_keys():
    with pytest.raises(ValueError, match="entity_keys"):
        MilestoneTableSpec.from_merge_on(["milestone_type"])


def test_aggregate_events_generic_entity_key(spark, house_spec):
    schema = StructType(
        [
            StructField("id_house", LongType(), False),
            StructField("ts_event", TimestampType(), False),
            StructField("sk_entity", LongType(), True),
            StructField("entity_type", StringType(), True),
        ]
    )
    events = spark.createDataFrame(
        [
            (7, _ts(2024, 1, 1), 100, "offer"),
            (7, _ts(2024, 6, 1), 200, "offer"),
        ],
        schema,
    )
    out = aggregate_events(events, house_spec).collect()
    assert len(out) == 1
    assert out[0].id_house == 7
    assert out[0].ts_first == _ts(2024, 1, 1)
    assert out[0].ts_last == _ts(2024, 6, 1)
    assert out[0].sk_entity_first == 100
    assert out[0].sk_entity_last == 200


def test_aggregate_and_merge_agents_shaped(spark, agents_spec):
    event_schema = StructType(
        [
            StructField("sk_user", LongType(), False),
            StructField("id_agent", LongType(), False),
            StructField("ts_event", TimestampType(), False),
            StructField("sk_entity", LongType(), True),
            StructField("entity_type", StringType(), True),
        ]
    )
    events = spark.createDataFrame(
        [
            (1, 10, _ts(2024, 1, 1), 100, "visit"),
            (1, 10, _ts(2024, 6, 1), 200, "visit"),
        ],
        event_schema,
    )
    aggregated = aggregate_events(events, agents_spec).withColumn(
        "milestone_type", F.lit("first_vb")
    )
    existing = empty_dim_df(spark, agents_spec)
    inserts, updates = prepare_merge_batch(
        existing, aggregated, agents_spec, bootstrap=False
    )
    assert inserts.count() == 1
    assert updates.count() == 0
    row = inserts.collect()[0]
    assert row.sk_user == 1
    assert row.id_agent == 10
    assert row.milestone_type == "first_vb"


def test_prepare_merge_keeps_sticky_on_incremental(spark, agents_spec):
    agg_schema = StructType(
        [
            StructField("sk_user", LongType(), False),
            StructField("id_agent", LongType(), False),
            StructField("milestone_type", StringType(), False),
            StructField("ts_first", TimestampType(), False),
            StructField("ts_last", TimestampType(), False),
            StructField("sk_entity_first", LongType(), True),
            StructField("sk_entity_last", LongType(), True),
            StructField("entity_type", StringType(), True),
        ]
    )
    existing = spark.createDataFrame(
        [
            (
                1,
                10,
                "first_vb",
                _ts(2024, 1, 1),
                _ts(2024, 2, 1),
                100,
                200,
                "visit",
            )
        ],
        agg_schema,
    )
    aggregated = spark.createDataFrame(
        [
            (
                1,
                99,
                "first_vb",
                _ts(2024, 1, 1),
                _ts(2024, 3, 1),
                100,
                300,
                "visit",
            )
        ],
        agg_schema,
    )
    inserts, updates = prepare_merge_batch(
        existing, aggregated, agents_spec, bootstrap=False
    )
    assert inserts.count() == 0
    assert updates.count() == 1
    row = updates.collect()[0]
    assert row.id_agent == 10  # sticky from existing
    assert row.ts_first == _ts(2024, 1, 1)
    assert row.ts_last == _ts(2024, 3, 1)
    assert row.sk_entity_last == 300


def test_build_scan_predicate_empty_existing(spark, agents_spec):
    existing = empty_dim_df(spark, agents_spec)
    pred = build_scan_predicate(
        existing, bootstrap=False, scan={"ts_column": "t.ts", "lookback_days": 2}
    )
    assert pred == "1 = 1"


def test_registry_from_metadata_yaml():
    yaml_text = """
database_name: dw_example
table_name: dim_example
milestones:
  sticky_columns: [id_agent]
  types:
    first_vb:
      milestone_type: first_vb
      sql_file: visit_events.sql
      scan:
        ts_column: vs.ts_schedule_confirmed
        lookback_days: 2
"""
    registry, sticky = load_milestones_from_metadata_yaml(yaml_text)
    assert sticky == ("id_agent",)
    assert "first_vb" in registry
    assert registry["first_vb"]["sql_file"] == "visit_events.sql"


def test_resolve_milestones_bootstrap_flag():
    registry = validate_milestones_registry(
        {
            "types": {
                "a": {
                    "milestone_type": "a",
                    "sql_file": "a.sql",
                    "scan": {"ts_column": "t.ts", "lookback_days": 1},
                },
                "b": {
                    "milestone_type": "b",
                    "sql_file": "b.sql",
                    "scan": {"ts_column": "t.ts", "lookback_days": 1},
                },
            }
        }
    )
    due = resolve_milestones_for_run(
        registry, milestones_to_run=["a"], bootstrap_milestones=["a"]
    )
    assert list(due.keys()) == ["a"]
    assert due["a"]["bootstrap"] is True
