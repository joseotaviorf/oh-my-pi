"""Grain simulation for visit_funnel_event — multiple sale_offer rows must collapse to one id_visit."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    BooleanType,
    DateType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

_REPO = Path(__file__).resolve().parents[8]
SQL_PATH = (
    _REPO
    / "dags"
    / "agents"
    / "enrich_agent_performance"
    / "queries"
    / "enrich"
    / "visit_funnel_event.sql"
)

TS_VISIT_CREATED = datetime(2025, 8, 10, 10, 0, 0)
TS_OFFER_SUBMITTED_EARLY = datetime(2025, 8, 11, 9, 0, 0)
TS_OFFER_SUBMITTED_LATE = datetime(2025, 8, 12, 9, 0, 0)
TS_OFFER_ACCEPTED = datetime(2025, 8, 13, 9, 0, 0)
TS_AGREEMENT_SIGNED = datetime(2025, 8, 14, 9, 0, 0)
ID_VISIT = 1001


@pytest.fixture(scope="module")
def spark():
    return (
        SparkSession.builder.appName("test_visit_funnel_event_grain")
        .master("local[1]")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse-visit-funnel-grain")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )


def _load_sql() -> str:
    return SQL_PATH.read_text(encoding="utf-8").format(
        reprocess_start_date="2025-08-01",
        load_end_date="2025-09-30",
    )


def _seed_tables(spark: SparkSession) -> None:
    visits = spark.createDataFrame(
        [
            (
                ID_VISIT,
                2001,
                3001,
                "SALE",
                TS_VISIT_CREATED,
                TS_VISIT_CREATED.date(),
                4001,
                None,
                None,
                None,
                0,
                False,
                True,
                False,
                False,
                True,
                False,
                TS_VISIT_CREATED,
                None,
                None,
                TS_VISIT_CREATED,
                None,
                None,
                TS_VISIT_CREATED,
            )
        ],
        StructType(
            [
                StructField("id_visit", LongType(), False),
                StructField("id_visitor", LongType(), False),
                StructField("id_house", LongType(), False),
                StructField("business_context", StringType(), False),
                StructField("ts_created", TimestampType(), False),
                StructField("dt_visit", DateType(), False),
                StructField("id_last_associated_agent", LongType(), False),
                StructField("visit_request_application_source", StringType(), True),
                StructField("ts_visit_registered", TimestampType(), True),
                StructField("id_first_associated_agent", LongType(), True),
                StructField("nbr_reschedule", IntegerType(), False),
                StructField("is_canceled", BooleanType(), False),
                StructField("is_completed", BooleanType(), False),
                StructField("is_unsuccessful", BooleanType(), False),
                StructField("is_stalled", BooleanType(), False),
                StructField("has_finisher_status", BooleanType(), False),
                StructField("is_vbba", BooleanType(), False),
                StructField("ts_visit", TimestampType(), False),
                StructField("ts_visit_rescheduled", TimestampType(), True),
                StructField("ts_visit_canceled", TimestampType(), True),
                StructField("ts_visit_done", TimestampType(), True),
                StructField("ts_visit_unsuccessful", TimestampType(), True),
                StructField("ts_visit_stalled", TimestampType(), True),
                StructField("ts_updated", TimestampType(), False),
            ]
        ),
    )
    visits.createOrReplaceTempView("visits")

    spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_visit", LongType(), False),
                StructField("id_author_user", LongType(), True),
                StructField("ts_created", TimestampType(), False),
                StructField("event_type", StringType(), False),
                StructField("channel", StringType(), True),
            ]
        ),
    ).createOrReplaceTempView("visit_status_events")

    spark.createDataFrame(
        [(3001, 5001)],
        StructType(
            [
                StructField("id", LongType(), False),
                StructField("id_region", LongType(), False),
            ]
        ),
    ).createOrReplaceTempView("house")

    spark.createDataFrame(
        [(5001, 6001)],
        StructType(
            [
                StructField("id", LongType(), False),
                StructField("id_city", LongType(), False),
            ]
        ),
    ).createOrReplaceTempView("region")

    spark.createDataFrame(
        [
            (
                2001,
                6001,
                "SALE",
                datetime(2025, 1, 1),
                None,
                4001,
            ),
            (
                2001,
                6001,
                "SALE",
                datetime(2025, 2, 1),
                None,
                4002,
            ),
        ],
        StructType(
            [
                StructField("id_visitor", LongType(), False),
                StructField("id_region", LongType(), False),
                StructField("business_context", StringType(), False),
                StructField("ts_status_started", TimestampType(), False),
                StructField("ts_status_ended", TimestampType(), True),
                StructField("id_user_agent", LongType(), False),
            ]
        ),
    ).createOrReplaceTempView("preferred_fixed_agent_history")

    spark.createDataFrame(
        [
            (
                3001,
                "AGENT",
                "4001",
                "KEY_HOLDER_ALLOCATED",
                datetime(2025, 1, 1),
                None,
            ),
            (
                3001,
                "AGENT",
                "4001",
                "KEY_HOLDER_ALLOCATED",
                datetime(2025, 6, 1),
                None,
            ),
        ],
        StructType(
            [
                StructField("id_house", LongType(), False),
                StructField("key_location", StringType(), False),
                StructField("key_holder_identifier", StringType(), False),
                StructField("event_type", StringType(), False),
                StructField("ts_entrance_started", TimestampType(), False),
                StructField("ts_entrance_ended", TimestampType(), True),
            ]
        ),
    ).createOrReplaceTempView("house_entrance_history")

    spark.createDataFrame(
        [
            (
                ID_VISIT,
                None,
                TS_OFFER_SUBMITTED_EARLY,
                None,
                None,
                None,
                datetime(2025, 8, 11, 12, 0, 0),
            ),
            (
                ID_VISIT,
                None,
                TS_OFFER_SUBMITTED_LATE,
                TS_OFFER_ACCEPTED,
                None,
                None,
                datetime(2025, 8, 13, 12, 0, 0),
            ),
            (
                None,
                ID_VISIT,
                None,
                None,
                TS_AGREEMENT_SIGNED,
                None,
                datetime(2025, 8, 14, 12, 0, 0),
            ),
        ],
        StructType(
            [
                StructField("id_visit_external", LongType(), True),
                StructField("id_visit_fifty_external", LongType(), True),
                StructField("ts_offer_submitted", TimestampType(), True),
                StructField("ts_offer_accepted", TimestampType(), True),
                StructField("ts_sale_agreement_signed", TimestampType(), True),
                StructField("ts_sale_agreement_canceled", TimestampType(), True),
                StructField("ts_updated", TimestampType(), False),
            ]
        ),
    ).createOrReplaceTempView("sale_offer")

    spark.createDataFrame(
        [(4001, "uuid-agent-4001")],
        StructType(
            [
                StructField("id_user", LongType(), False),
                StructField("uuid_person", StringType(), False),
            ]
        ),
    ).createOrReplaceTempView("agent_unified_identity")


def _sql_with_temp_views(sql: str) -> str:
    replacements = {
        "datalake_visit.visits": "visits",
        "datalake_visit.visit_status_events": "visit_status_events",
        "datalake_ebdb_listing.house": "house",
        "datalake_region.region": "region",
        "datalake_ebdb_agents.preferred_fixed_agent_history": "preferred_fixed_agent_history",
        "datalake_ebdb_listing.house_entrance_history": "house_entrance_history",
        "datalake_sale_offer.sale_offer": "sale_offer",
        "datalake_ebdb_agent_events.agent_unified_identity": "agent_unified_identity",
    }
    for source, view in replacements.items():
        sql = sql.replace(source, view)
    return sql


def test_visit_funnel_event_emits_one_row_per_visit_with_multiple_offers(spark):
    """Regression: direct sale_offer join fan-out broke Delta merge_on id_visit in prod."""
    _seed_tables(spark)
    result = spark.sql(_sql_with_temp_views(_load_sql()))

    assert result.count() == 1
    assert result.select("id_visit").distinct().count() == 1

    row = result.collect()[0]
    assert row.id_visit == ID_VISIT
    assert row.is_offer_submitted == 1
    assert row.is_offer_accepted == 1
    assert row.is_agreement_signed == 1
    assert row.ts_offer_submitted == TS_OFFER_SUBMITTED_EARLY
    assert row.ts_offer_accepted == TS_OFFER_ACCEPTED
    assert row.ts_sale_agreement_signed == TS_AGREEMENT_SIGNED
    # Two overlapping PFA rows: pick latest ts_status_started (4002), not MAX(id).
    assert row.id_user_fixed_agent == 4002
    assert row.is_pfa_visit == 0
    assert row.is_crcc_visit == 1


def test_raw_sale_offer_join_would_fan_out_without_aggregation(spark):
    """Documents why offer_by_visit + visit_grain are required (not arbitrary dedup)."""
    _seed_tables(spark)
    fanout = spark.sql(
        f"""
        SELECT v.id_visit, so.ts_updated
        FROM visits AS v
        LEFT JOIN sale_offer AS so
            ON v.id_visit = so.id_visit_external
            OR v.id_visit = so.id_visit_fifty_external
        WHERE v.id_visit = {ID_VISIT}
        """
    )
    assert fanout.count() > 1
