"""
Pytest fixtures for core_region_history Spark job tests.
"""

from datetime import datetime
from unittest.mock import patch

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
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
]

BU_EVENT_CONFIGS = [
    {"tracked_col": "hub_name", "target_col": "hub_name", "target_type": "string"},
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
]

CONFIG_MAP_BUR = {
    "ENTITY_TYPE": "HUB_REGION_HISTORY",
    "BUSINESS_UNIT_REGION_HISTORY_TRANSACTIONAL_TABLE": "test.business_unit_region",
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
            "c",
            datetime(2024, 3, 1, 8, 0, 0),
            datetime(2024, 3, 1, 8, 0, 1),
        ),
        (
            "100",
            "20",
            "10",
            "RENT",
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
            "c",
            datetime(2024, 4, 1, 8, 0, 0),
            datetime(2024, 4, 1, 8, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_bu_df(spark_session):
    """CDC rows for business_unit: INSERT then UPDATE where only hub_name changes."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("hub_name", StringType(), True),
            StructField("sdr_type", StringType(), True),
            StructField("lead_types", StringType(), True),
            StructField("negotiation_type", StringType(), True),
            StructField("operational_context", StringType(), True),
            StructField("business_context", StringType(), True),
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
            "u",
            datetime(2024, 3, 10, 9, 0, 0),
            datetime(2024, 3, 10, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)
