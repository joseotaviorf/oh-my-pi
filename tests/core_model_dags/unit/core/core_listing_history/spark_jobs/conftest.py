"""
Pytest fixtures for core_listing_history Spark job tests.
"""

from datetime import datetime
from unittest.mock import patch

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    BooleanType,
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

# Temp view names (session-scoped) — must match CONFIG_MAP table strings.
TEST_LBC_TABLE = "listing_hist_lbc"
TEST_IMOVEL_TABLE = "listing_hist_imovel"
TEST_AUX_TABLE = "listing_hist_aux"
TEST_CATEGORY_TABLE = "listing_hist_category"

LBC_COMMON_EVENT_CONFIGS = [
    {"tracked_col": "ownership", "target_col": "ownership", "target_type": "string"},
    {
        "tracked_col": "firstPublicationDate",
        "target_col": "ts_first_publication",
        "target_type": "string",
    },
    {
        "tracked_col": "lastPublicationDate",
        "target_col": "ts_last_publication",
        "target_type": "string",
    },
]

LBC_SALE_EVENT_CONFIGS = [
    {"tracked_col": "status", "target_col": "status", "target_type": "string"},
    {"tracked_col": "statusReason", "target_col": "status_reason", "target_type": "string"},
]

RENT_PRICE_EVENT_CONFIGS = [
    {"tracked_col": "aluguel", "target_col": "price", "target_type": "int"},
    {"tracked_col": "valorTotal", "target_col": "total_value", "target_type": "int"},
    {"tracked_col": "condominio", "target_col": "condo_value", "target_type": "int"},
    {"tracked_col": "iptu", "target_col": "iptu_value", "target_type": "int"},
    {"tracked_col": "tipoCondominio", "target_col": "condo_type", "target_type": "string"},
    {"tracked_col": "tipoIptu", "target_col": "iptu_type", "target_type": "string"},
]

SALE_PRICE_EVENT_CONFIGS = [
    {"tracked_col": "salePrice", "target_col": "price", "target_type": "int"},
    {"tracked_col": "valorTotal", "target_col": "total_value", "target_type": "int"},
    {"tracked_col": "condominio", "target_col": "condo_value", "target_type": "int"},
    {"tracked_col": "iptu", "target_col": "iptu_value", "target_type": "int"},
    {"tracked_col": "tipoCondominio", "target_col": "condo_type", "target_type": "string"},
    {"tracked_col": "tipoIptu", "target_col": "iptu_type", "target_type": "string"},
]

AUX_EVENT_CONFIGS = [
    {"tracked_col": "status", "target_col": "status", "target_type": "string"},
    {"tracked_col": "status_reason", "target_col": "status_reason", "target_type": "string"},
    {"tracked_col": "listing_version", "target_col": "version", "target_type": "int"},
    {"tracked_col": "is_extended_rental", "target_col": "is_extended_rental", "target_type": "boolean"},
    {
        "tracked_col": "has_termination_canceled",
        "target_col": "has_termination_canceled",
        "target_type": "boolean",
    },
    {"tracked_col": "listing_category", "target_col": "category", "target_type": "string"},
]

CONFIG_MAP = {
    "ENTITY_TYPE": "LISTING_HISTORY",
    "LBC_TRANSACTIONAL_TABLE": TEST_LBC_TABLE,
    "HOUSE_TRANSACTIONAL_TABLE": TEST_IMOVEL_TABLE,
    "AUX_LBC_STATUS_VERSION_ORDER_TABLE": TEST_AUX_TABLE,
    "AUX_HOUSE_LISTING_CATEGORY_TABLE": TEST_CATEGORY_TABLE,
    "merge_on_historical": [
        "id_house_listing",
        "business_context",
        "event_name",
        "ts_transaction",
        "year",
        "month",
        "day",
    ],
    "when_matched_update_condition_historical": "FALSE",
    "lbc_common_event_configs": LBC_COMMON_EVENT_CONFIGS,
    "lbc_sale_event_configs": LBC_SALE_EVENT_CONFIGS,
    "rent_price_event_configs": RENT_PRICE_EVENT_CONFIGS,
    "sale_price_event_configs": SALE_PRICE_EVENT_CONFIGS,
    "aux_event_configs": AUX_EVENT_CONFIGS,
}


def _config_side_effect(key, required=False, default=None):
    if key in CONFIG_MAP:
        return CONFIG_MAP[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreListingHistoryTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def mock_configuration_listing_history():
    """Mock get_config for CoreListingHistorySparkJob."""
    with patch(
        "dags.core.core_listing_history.spark_jobs.load_core_listing_history"
        ".CoreListingHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect
        yield mock_get_config


@pytest.fixture
def lbc_transactional_df(spark_session):
    """CDC rows for ListingBusinessContext: RENT house 99 + SALE house 100."""
    schema = StructType(
        [
            StructField("imovelId", StringType(), True),
            StructField("businessContext", StringType(), True),
            StructField("ownership", StringType(), True),
            StructField("firstPublicationDate", StringType(), True),
            StructField("lastPublicationDate", StringType(), True),
            StructField("status", StringType(), True),
            StructField("statusReason", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    t0 = datetime(2026, 1, 1, 8, 0, 0)
    t1 = datetime(2026, 1, 2, 9, 0, 0)
    t_cdc = datetime(2026, 1, 1, 0, 0, 1)
    data = [
        (
            "99",
            "RENT",
            "STANDARD",
            "2026-01-01",
            "2026-01-01",
            None,
            None,
            "c",
            t0,
            t_cdc,
        ),
        (
            "99",
            "RENT",
            "THIRD_PARTY",
            "2026-01-01",
            "2026-01-01",
            None,
            None,
            "u",
            t1,
            t_cdc,
        ),
        (
            "100",
            "SALE",
            "STANDARD",
            "2026-01-01",
            "2026-01-01",
            "ACTIVE",
            "NONE",
            "c",
            t0,
            t_cdc,
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def imovel_transactional_df(spark_session):
    """CDC rows for imovel: RENT house 99 + SALE house 100."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("aluguel", IntegerType(), True),
            StructField("salePrice", IntegerType(), True),
            StructField("valorTotal", IntegerType(), True),
            StructField("condominio", IntegerType(), True),
            StructField("iptu", IntegerType(), True),
            StructField("tipoCondominio", StringType(), True),
            StructField("tipoIptu", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    t0 = datetime(2026, 1, 1, 12, 0, 0)
    t1 = datetime(2026, 1, 5, 12, 0, 0)
    t2 = datetime(2026, 1, 3, 12, 0, 0)
    tc = datetime(2026, 1, 1, 0, 0, 1)
    data = [
        ("99", 1000, None, 1200, 100, 50, "FIXED", "MONTHLY", "c", t0, tc),
        ("99", 1100, None, 1200, 100, 50, "FIXED", "MONTHLY", "u", t1, tc),
        ("100", None, 500000, 520000, 200, 80, "FIXED", "YEARLY", "c", t0, tc),
        ("100", None, 520000, 520000, 200, 80, "FIXED", "YEARLY", "u", t2, tc),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def aux_lbc_status_df(spark_session):
    """aux__lbc_status_version_order — RENT house 99 version 0 only."""
    schema = StructType(
        [
            StructField("id_house", StringType(), True),
            StructField("listing_version", IntegerType(), True),
            StructField("ts_state_started", TimestampType(), True),
            StructField("ts_state_ended", TimestampType(), True),
            StructField("status", StringType(), True),
            StructField("status_reason", StringType(), True),
            StructField("is_extended_rental", BooleanType(), True),
            StructField("has_termination_canceled", BooleanType(), True),
        ]
    )
    data = [
        (
            "99",
            0,
            datetime(2026, 1, 1, 0, 0, 0),
            None,
            "LISTED",
            "NEW",
            False,
            False,
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_listing_category_df(spark_session):
    """aux__house_listing_category — matches id_house_listing 99000."""
    schema = StructType(
        [
            StructField("id_house", StringType(), True),
            StructField("id_house_listing", IntegerType(), True),
            StructField("listing_category", StringType(), True),
        ]
    )
    data = [("99", 99000, "APARTMENT")]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_listing_category_empty_df(spark_session):
    """Category table with no rows (left join → null category for NA coalesce test)."""
    schema = StructType(
        [
            StructField("id_house", StringType(), True),
            StructField("id_house_listing", IntegerType(), True),
            StructField("listing_category", StringType(), True),
        ]
    )
    return spark_session.createDataFrame([], schema)


def _load_transactional_side_effect(lbc_df, imovel_df):
    """Return LBC or imovel CDC frame based on table name."""

    def _fn(spark, table_name, args):
        if table_name == TEST_LBC_TABLE:
            return lbc_df
        if table_name == TEST_IMOVEL_TABLE:
            return imovel_df
        raise AssertionError(f"Unexpected transactional table: {table_name}")

    return _fn


@pytest.fixture
def register_listing_history_views(
    spark_session,
    lbc_transactional_df,
    imovel_transactional_df,
    aux_lbc_status_df,
    house_listing_category_df,
):
    """Register temp views used by spark.read.table in the job."""
    lbc_transactional_df.createOrReplaceTempView(TEST_LBC_TABLE)
    imovel_transactional_df.createOrReplaceTempView(TEST_IMOVEL_TABLE)
    aux_lbc_status_df.createOrReplaceTempView(TEST_AUX_TABLE)
    house_listing_category_df.createOrReplaceTempView(TEST_CATEGORY_TABLE)
    yield
    for name in (
        TEST_LBC_TABLE,
        TEST_IMOVEL_TABLE,
        TEST_AUX_TABLE,
        TEST_CATEGORY_TABLE,
    ):
        try:
            spark_session.catalog.dropTempView(name)
        except Exception:
            pass


@pytest.fixture
def register_listing_history_views_no_category(
    spark_session,
    lbc_transactional_df,
    imovel_transactional_df,
    aux_lbc_status_df,
    house_listing_category_empty_df,
):
    """Same as register_listing_history_views but empty category table."""
    lbc_transactional_df.createOrReplaceTempView(TEST_LBC_TABLE)
    imovel_transactional_df.createOrReplaceTempView(TEST_IMOVEL_TABLE)
    aux_lbc_status_df.createOrReplaceTempView(TEST_AUX_TABLE)
    house_listing_category_empty_df.createOrReplaceTempView(TEST_CATEGORY_TABLE)
    yield
    for name in (
        TEST_LBC_TABLE,
        TEST_IMOVEL_TABLE,
        TEST_AUX_TABLE,
        TEST_CATEGORY_TABLE,
    ):
        try:
            spark_session.catalog.dropTempView(name)
        except Exception:
            pass
