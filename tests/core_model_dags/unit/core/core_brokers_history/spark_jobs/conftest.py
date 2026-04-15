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

COMPANY_HISTORY_EVENT_CONFIGS = [
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

COMPANY_PRODUCT_HISTORY_EVENT_CONFIGS = [
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

CONFIG_MAP_COMPANY = {
    "ENTITY_TYPE": "BROKER",
    "COMPANY_HISTORY_TRANSACTIONAL_TABLE": "test.transactional_company",
    "merge_on_historical": ["id_event"],
    "when_matched_update_condition_historical": None,
    "company_history_event_configs": COMPANY_HISTORY_EVENT_CONFIGS,
}

CONFIG_MAP_COMPANY_PRODUCT = {
    "ENTITY_TYPE": "BROKER",
    "COMPANY_PRODUCT_HISTORY_TRANSACTIONAL_TABLE": "test.transactional_company_product",
    "merge_on_historical": ["id_event"],
    "when_matched_update_condition_historical": None,
    "company_product_history_event_configs": COMPANY_PRODUCT_HISTORY_EVENT_CONFIGS,
}


def _config_side_effect_company(key, required=False, default=None):
    if key in CONFIG_MAP_COMPANY:
        return CONFIG_MAP_COMPANY[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


def _config_side_effect_company_product(key, required=False, default=None):
    if key in CONFIG_MAP_COMPANY_PRODUCT:
        return CONFIG_MAP_COMPANY_PRODUCT[key]
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
def mock_configuration_company_history():
    with patch(
        "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
        ".CoreBrokersHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect_company
        yield mock_get_config


@pytest.fixture
def mock_configuration_company_product_history():
    with patch(
        "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
        ".CoreBrokersHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect_company_product
        yield mock_get_config


@pytest.fixture
def transactional_company_df(spark_session):
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
            "10",
            "Acme Ltd",
            "Acme",
            "ACTIVE",
            "c",
            datetime(2026, 1, 10, 8, 0, 0),
            datetime(2026, 1, 10, 8, 0, 1),
        ),
        (
            "10",
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
            StructField("id_company", StringType(), True),
            StructField("id_product", StringType(), True),
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
