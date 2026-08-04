"""
Pytest fixtures for core_region_history Spark job tests.
"""

from datetime import datetime
from unittest.mock import patch

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

BUR_EVENT_CONFIGS = [
    {
        "tracked_col": "business_context",
        "target_col": "business_context",
        "target_type": "string",
    },
    {
        "tracked_col": "created_at",
        "target_col": "ts_created",
        "target_type": "timestamp",
        "value_precision": "millisecond",
    },
    {
        "tracked_col": "is_deleted",
        "target_col": "is_deleted",
        "target_type": "string",
    },
]

BU_EVENT_CONFIGS = [
    {"tracked_col": "name", "target_col": "hub_name", "target_type": "string"},
    {"tracked_col": "sdr_type", "target_col": "sdr_type", "target_type": "string"},
    {"tracked_col": "lead_types", "target_col": "lead_types", "target_type": "string"},
    {
        "tracked_col": "negotiation_type",
        "target_col": "negotiation_type",
        "target_type": "string",
    },
    {
        "tracked_col": "operational_context",
        "target_col": "operational_context",
        "target_type": "string",
    },
    {
        "tracked_col": "business_context",
        "target_col": "business_context",
        "target_type": "string",
    },
    {
        "tracked_col": "created_at",
        "target_col": "ts_created",
        "target_type": "timestamp",
        "value_precision": "millisecond",
    },
]

CONFIG_MAP_BUR = {
    "ENTITY_TYPE": "HUB_REGION_HISTORY",
    "BUSINESS_UNIT_REGION_HISTORY_TRANSACTIONAL_TABLE": "test.business_unit_region",
    "BUSINESS_UNIT_REGION_AUD_TRANSACTIONAL_TABLE": "test.business_unit_region_aud",
    "merge_on_historical": ["id_event"],
    "business_unit_region_history_event_configs": BUR_EVENT_CONFIGS,
}

CONFIG_MAP_BU = {
    "ENTITY_TYPE": "HUB_REGION_HISTORY",
    "BUSINESS_UNIT_HISTORY_TRANSACTIONAL_TABLE": "test.business_unit",
    "merge_on_historical": ["id_event"],
    "business_unit_history_event_configs": BU_EVENT_CONFIGS,
}


def _config_side_effect_bur(key, required=False, default=None):
    if key in CONFIG_MAP_BUR:
        return CONFIG_MAP_BUR[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


def _config_side_effect_bu(key, required=False, default=None):
    if key in CONFIG_MAP_BU:
        return CONFIG_MAP_BU[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreRegionHistoryTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def mock_configuration_bur():
    """Mock get_config for business_unit_region_history."""
    with patch(
        "dags.core.core_region_history.spark_jobs.load_core_region_history"
        ".CoreRegionHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect_bur
        yield mock_get_config


@pytest.fixture
def mock_configuration_bu():
    """Mock get_config for business_unit_history."""
    with patch(
        "dags.core.core_region_history.spark_jobs.load_core_region_history"
        ".CoreRegionHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect_bu
        yield mock_get_config


@pytest.fixture
def transactional_bur_df(spark_session):
    """CDC rows for business_unit_region: INSERT then UPDATE with context change."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("business_unit_id", StringType(), True),
            StructField("region_id", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "100",
            "20",
            "10",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
            "c",
            datetime(2024, 3, 1, 8, 0, 0),
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "100",
            "20",
            "10",
            "RENT",
            datetime(2024, 3, 1, 8, 0, 0),
            "u",
            datetime(2024, 3, 5, 10, 0, 0),
            datetime(2024, 3, 5, 10, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_bur_null_context_df(spark_session):
    """CDC rows for business_unit_region where business_context is null on INSERT."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("business_unit_id", StringType(), True),
            StructField("region_id", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "200",
            "30",
            "10",
            None,
            datetime(2024, 4, 1, 8, 0, 0),
            "c",
            datetime(2024, 4, 1, 8, 0, 0),
            datetime(2024, 4, 1, 8, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_bur_reassociation_df(spark_session):
    """Two junction ids for the same (region, business_unit) pair — re-association."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("business_unit_id", StringType(), True),
            StructField("region_id", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "100",
            "20",
            "10",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
            "c",
            datetime(2024, 3, 1, 8, 0, 0),
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "101",
            "20",
            "10",
            "RENT",
            datetime(2024, 6, 1, 9, 0, 0),
            "c",
            datetime(2024, 6, 1, 9, 0, 0),
            datetime(2024, 6, 1, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_bur_with_zero_key_df(spark_session):
    """Valid junction plus sentinel (0,0) row — only valid junction should emit events."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("business_unit_id", StringType(), True),
            StructField("region_id", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "100",
            "20",
            "10",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
            "c",
            datetime(2024, 3, 1, 8, 0, 0),
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "999",
            "0",
            "0",
            "SALE",
            datetime(1970, 1, 1, 0, 0, 0),
            "c",
            datetime(2024, 3, 2, 8, 0, 0),
            datetime(2024, 3, 2, 8, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_bur_snapshot_duplicate_fk_df(spark_session):
    """Snapshot batch: two CDC rows share junction id and ts with conflicting FKs."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("business_unit_id", StringType(), True),
            StructField("region_id", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    snapshot_ts = datetime(2024, 3, 1, 8, 0, 0)
    created_at = datetime(2024, 3, 1, 8, 0, 0)
    data = [
        (
            "100",
            "20",
            "99",
            "SALE",
            created_at,
            "r",
            snapshot_ts,
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "100",
            "20",
            "10",
            "SALE",
            created_at,
            "r",
            snapshot_ts,
            datetime(2024, 3, 1, 8, 0, 2),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


# --- business_unit_region audit (tombstone injection) ---------------------------------

_BUR_AUD_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("rev", IntegerType(), True),
        StructField("revtype", IntegerType(), True),
        StructField("business_unit_id", StringType(), True),
        StructField("region_id", StringType(), True),
        StructField("ts_database_transaction", TimestampType(), True),
    ]
)


@pytest.fixture
def bur_aud_empty_df(spark_session):
    """No audit revisions — the CDC stream passes through unchanged."""
    return spark_session.createDataFrame([], _BUR_AUD_SCHEMA)


@pytest.fixture
def bur_aud_delete_df(spark_session):
    """One delete revision (revtype=2) for junction 100, carrying both FKs.

    Also holds an update revision (revtype=1) that must not become a tombstone.
    """
    data = [
        ("100", 7, 2, "20", "10", datetime(2024, 4, 1, 10, 0, 0)),
        ("100", 6, 1, "20", "10", datetime(2024, 3, 5, 10, 0, 0)),
    ]
    return spark_session.createDataFrame(data, _BUR_AUD_SCHEMA)


@pytest.fixture
def bur_aud_duplicate_revision_df(spark_session):
    """The same delete revision re-observed by two bulk snapshot batches."""
    data = [
        ("100", 7, 2, "20", "10", datetime(2024, 4, 1, 10, 0, 0)),
        ("100", 7, 2, "20", "10", datetime(2024, 4, 3, 22, 0, 0)),
    ]
    return spark_session.createDataFrame(data, _BUR_AUD_SCHEMA)


@pytest.fixture
def bur_aud_delete_at_snapshot_ts_df(spark_session):
    """Delete revision landing on the same instant as a CDC snapshot row."""
    data = [("100", 7, 2, "20", "10", datetime(2024, 4, 1, 12, 0, 0))]
    return spark_session.createDataFrame(data, _BUR_AUD_SCHEMA)


@pytest.fixture
def transactional_bur_snapshot_at_delete_ts_df(spark_session):
    """Insert, then a snapshot row at the instant the audit delete was recorded.

    The snapshot row carries a non-null ``ts_cdc_transaction``; the injected tombstone
    carries none, so without the tombstone priority column the snapshot row would win
    canonicalization under DESC NULLS LAST.
    """
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("business_unit_id", StringType(), True),
            StructField("region_id", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    created_at = datetime(2024, 3, 1, 8, 0, 0)
    data = [
        (
            "100",
            "20",
            "10",
            "SALE",
            created_at,
            "c",
            datetime(2024, 3, 1, 8, 0, 0),
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "100",
            "20",
            "10",
            "SALE",
            created_at,
            "r",
            datetime(2024, 4, 1, 12, 0, 0),
            datetime(2024, 4, 1, 12, 0, 5),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_bur_recreated_df(spark_session):
    """Insert, then an update *after* the audit delete instant — a resurrected junction."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("business_unit_id", StringType(), True),
            StructField("region_id", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    created_at = datetime(2024, 3, 1, 8, 0, 0)
    data = [
        (
            "100",
            "20",
            "10",
            "SALE",
            created_at,
            "c",
            datetime(2024, 3, 1, 8, 0, 0),
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "100",
            "20",
            "10",
            "RENT",
            created_at,
            "u",
            datetime(2024, 5, 1, 9, 0, 0),
            datetime(2024, 5, 1, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_bu_df(spark_session):
    """CDC rows for business_unit: INSERT then UPDATE where only hub_name changes."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("sdr_type", StringType(), True),
            StructField("lead_types", StringType(), True),
            StructField("negotiation_type", StringType(), True),
            StructField("operational_context", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "1",
            "Hub SP",
            "SDR_A",
            "[sale,rent]",
            "STANDARD",
            "SAO_PAULO",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
            "c",
            datetime(2024, 3, 1, 8, 0, 0),
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "1",
            "Hub São Paulo",
            "SDR_A",
            "[sale,rent]",
            "STANDARD",
            "SAO_PAULO",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
            "u",
            datetime(2024, 3, 10, 9, 0, 0),
            datetime(2024, 3, 10, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)
