"""
Pytest fixtures for core_brokers_history Spark job tests.
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

BROKERS_HISTORY_EVENT_CONFIGS = [
    {
        "tracked_col": "company_name",
        "target_col": "company_name",
        "target_type": "string",
    },
    {
        "tracked_col": "trade_name",
        "target_col": "trade_name",
        "target_type": "string",
    },
    {
        "tracked_col": "status",
        "target_col": "status",
        "target_type": "string",
    },
]

BROKER_PRODUCTS_HISTORY_EVENT_CONFIGS = [
    {
        "tracked_col": "product_settings",
        "target_col": "product_settings",
        "target_type": "string",
    },
    {
        "tracked_col": "status",
        "target_col": "status",
        "target_type": "string",
    },
]

CONFIG_MAP_BROKERS_HISTORY = {
    "ENTITY_TYPE": "BROKER",
    "BROKERS_HISTORY_TRANSACTIONAL_TABLE": "test.transactional_company",
    "BROKER_PRODUCTS_HISTORY_TRANSACTIONAL_TABLE": "test.transactional_company_product",
    "merge_on_historical": ["id_event"],
    "when_matched_update_condition_historical": None,
    "brokers_history_event_configs": BROKERS_HISTORY_EVENT_CONFIGS,
}

CONFIG_MAP_BROKER_PRODUCTS_HISTORY = {
    "ENTITY_TYPE": "BROKER",
    "BROKER_PRODUCTS_HISTORY_TRANSACTIONAL_TABLE": "test.transactional_company_product",
    "merge_on_historical": ["id_event"],
    "when_matched_update_condition_historical": None,
    "broker_products_history_event_configs": BROKER_PRODUCTS_HISTORY_EVENT_CONFIGS,
}


def _config_side_effect_brokers_history(key, required=False, default=None):
    if key in CONFIG_MAP_BROKERS_HISTORY:
        return CONFIG_MAP_BROKERS_HISTORY[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


def _config_side_effect_broker_products_history(key, required=False, default=None):
    if key in CONFIG_MAP_BROKER_PRODUCTS_HISTORY:
        return CONFIG_MAP_BROKER_PRODUCTS_HISTORY[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreBrokersHistoryTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def mock_configuration_brokers_history():
    with patch(
        "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
        ".CoreBrokersHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect_brokers_history
        yield mock_get_config


@pytest.fixture
def mock_configuration_broker_products_history():
    with patch(
        "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
        ".CoreBrokersHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect_broker_products_history
        yield mock_get_config


@pytest.fixture
def transactional_company_df(spark_session):
    """Company id matches company_id in transactional_company_product_df (3P scope)."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("company_name", StringType(), True),
            StructField("trade_name", StringType(), True),
            StructField("status", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "1",
            "Acme Ltd",
            "Acme",
            "ACTIVE",
            "c",
            datetime(2026, 1, 10, 8, 0, 0),
            datetime(2026, 1, 10, 8, 0, 1),
        ),
        (
            "1",
            "Acme Ltd",
            "Acme",
            "INACTIVE",
            "u",
            datetime(2026, 1, 11, 9, 0, 0),
            datetime(2026, 1, 11, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_company_product_df(spark_session):
    schema = StructType(
        [
            StructField("company_id", StringType(), True),
            StructField("product_id", StringType(), True),
            StructField("product_settings", StringType(), True),
            StructField("status", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "1",
            "30",
            "{}",
            "ACTIVE",
            "c",
            datetime(2026, 1, 10, 8, 0, 0),
            datetime(2026, 1, 10, 8, 0, 1),
        ),
        (
            "1",
            "30",
            "{}",
            "ENDED",
            "u",
            datetime(2026, 1, 11, 9, 0, 0),
            datetime(2026, 1, 11, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_company_no_three_p_match_df(spark_session):
    """Company rows with id that never appears with product 27/30 in CP fixture."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("company_name", StringType(), True),
            StructField("trade_name", StringType(), True),
            StructField("status", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "99",
            "Other Co",
            "O",
            "ACTIVE",
            "c",
            datetime(2026, 1, 10, 8, 0, 0),
            datetime(2026, 1, 10, 8, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_company_product_non_broker_df(spark_session):
    """Product id outside 27/30 — must produce no history rows after filter."""
    schema = StructType(
        [
            StructField("company_id", StringType(), True),
            StructField("product_id", StringType(), True),
            StructField("product_settings", StringType(), True),
            StructField("status", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "1",
            "5",
            "{}",
            "ACTIVE",
            "c",
            datetime(2026, 1, 10, 8, 0, 0),
            datetime(2026, 1, 10, 8, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)
