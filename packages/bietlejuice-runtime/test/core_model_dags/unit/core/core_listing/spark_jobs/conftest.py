"""
Pytest fixtures for core_listing Spark job tests.
"""

from datetime import datetime
from unittest.mock import Mock, patch

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    BooleanType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from dags.core.core_listing.spark_jobs.load_core_listing import CoreListingSparkJob


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreListingTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def house_df(spark_session):
    """Create a sample house DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("rent", IntegerType(), True),
            StructField("sale_price", IntegerType(), True),
            StructField("total_value", IntegerType(), True),
            StructField("condo", IntegerType(), True),
            StructField("iptu", IntegerType(), True),
            StructField("condo_type", StringType(), True),
            StructField("iptu_type", StringType(), True),
        ]
    )

    data = [
        (1001, 2500, None, 3000, 400, 100, "Normal", "Normal"),
        (1002, 3000, 500000, 3500, 350, 150, "IncluidoNoAluguel", "Normal"),
        (2001, None, 800000, 800000, 500, 200, "Normal", "NaoInformado"),
        (2003, None, 600000, 600000, None, None, "NaoExiste", "NaoExiste"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def listing_business_context_df(spark_session):
    """Create a sample listing_business_context DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_house", LongType(), True),
            StructField("ownership", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("status", StringType(), True),
            StructField("status_reason", StringType(), True),
            StructField("ts_first_publication", TimestampType(), True),
            StructField("ts_last_publication", TimestampType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
        ]
    )

    data = [
        # RENT listings
        (
            1,  # id
            1001,  # id_house
            "STANDARD",  # ownership
            "RENT",  # business_context
            "PUBLISHED",  # status
            None,  # status_reason
            datetime(2024, 1, 15, 12, 0),  # ts_first_publication
            datetime(2025, 3, 10, 10, 0),  # ts_last_publication
            datetime(2024, 1, 10, 10, 0),  # ts_created
            datetime(2025, 7, 8, 10, 0),  # ts_updated
        ),
        # House 1002 - RENT context
        (
            8,  # id
            1002,  # id_house (dual context: RENT + SALE)
            "STANDARD",  # ownership
            "RENT",  # business_context
            "SUSPENDED",  # status
            "RENTED",  # status_reason
            datetime(2024, 4, 2, 10, 0),  # ts_first_publication
            datetime(2024, 4, 15, 10, 0),  # ts_last_publication
            datetime(2024, 4, 1, 10, 0),  # ts_created
            datetime(2024, 4, 19, 10, 0),  # ts_updated
        ),
        # SALE listings
        # House 1002 - SALE context
        (
            9,  # id
            1002,  # id_house
            "STANDARD",  # ownership
            "SALE",  # business_context
            "SUSPENDED",  # status
            None,  # status_reason
            datetime(2024, 8, 15, 10, 0),  # ts_first_publication
            datetime(2025, 5, 20, 10, 0),  # ts_last_publication
            datetime(2024, 8, 12, 10, 0),  # ts_created
            datetime(2025, 5, 21, 10, 0),  # ts_updated
        ),
        # House 2001
        (
            5,  # id
            2001,  # id_house
            "THIRD_PARTY",  # ownership
            "SALE",  # business_context
            "PUBLISHED",  # status
            None,  # status_reason
            datetime(2024, 3, 12, 10, 0),  # ts_first_publication
            datetime(2024, 3, 14, 10, 0),  # ts_last_publication
            datetime(2024, 3, 10, 10, 0),  # ts_created
            datetime(2024, 3, 15, 11, 0),  # ts_updated
        ),
        # House 2003 - SALE listing that should be filtered out (ts_created <= 2022 AND ts_updated IS NULL)
        (
            6,  # id
            2003,  # id_house
            "STANDARD",  # ownership
            "SALE",  # business_context
            "EDITING",  # status
            None,  # status_reason
            None,  # ts_first_publication
            None,  # ts_last_publication
            datetime(2022, 6, 1, 10, 0),  # ts_created (year <= 2022)
            None,  # ts_updated (NULL)
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def aux_lbc_status_version_order_df(spark_session):
    """Create a sample aux__lbc_status_version_order DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_house", LongType(), True),
            StructField("listing_version", IntegerType(), True),
            StructField("status", StringType(), True),
            StructField("status_reason", StringType(), True),
            StructField("is_extended_rental", BooleanType(), True),
            StructField("has_termination_canceled", BooleanType(), True),
            StructField("ts_state_started", TimestampType(), True),
            StructField("ts_state_ended", TimestampType(), True),
        ]
    )

    data = [
        # House 1001
        (
            1001,  # id_house
            0,  # listing_version
            "EDITING",  # status
            None,  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2024, 1, 10, 10, 0),  # ts_state_started
            datetime(2024, 1, 15, 11, 0),  # ts_state_ended
        ),
        (
            1001,  # id_house
            1,  # listing_version
            "PUBLISHED",  # status
            None,  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2024, 1, 15, 11, 0),  # ts_state_started
            datetime(2024, 2, 18, 11, 0),  # ts_state_ended
        ),
        (
            1001,  # id_house
            1,  # listing_version
            "SUSPENDED",  # status
            "RENTED",  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2024, 2, 18, 11, 0),  # ts_state_started
            datetime(2025, 2, 20, 10, 0),  # ts_state_ended
        ),
        (
            1001,  # id_house
            2,  # listing_version
            "PUBLISHED",  # status
            None,  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2025, 2, 20, 10, 0),  # ts_state_started
            datetime(2025, 3, 11, 10, 0),  # ts_state_ended
        ),
        (
            1001,  # id_house
            2,  # listing_version
            "UNPUBLISHED",  # status
            None,  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2025, 3, 11, 10, 0),  # ts_state_started
            datetime(2025, 7, 8, 10, 0),  # ts_state_ended
        ),
        (
            1001,  # id_house
            3,  # listing_version
            "PUBLISHED",  # status
            None,  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2025, 7, 8, 10, 0),  # ts_state_started
            None,  # current state
        ),
        # House 1002 - RENT context (same house has SALE context too)
        (
            1002,  # id_house
            1,  # listing_version
            "PUBLISHED",  # status
            None,  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2024, 4, 1, 10, 0),  # ts_state_started
            datetime(2025, 4, 19, 10, 0),  # ts_state_ended
        ),
        (
            1002,  # id_house
            1,  # listing_version
            "SUSPENDED",  # status
            "RENTED",  # status_reason
            False,  # is_extended_rental
            False,  # has_termination_canceled
            datetime(2025, 4, 19, 10, 0),  # ts_state_started
            None,  # ts_state_ended (current)
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def aux_house_listing_category_df(spark_session):
    """Create a sample aux__house_listing_category DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_house", LongType(), True),
            StructField("id_house_listing", LongType(), True),
            StructField("listing_category", StringType(), True),
        ]
    )

    data = [
        (1001, 1001000, None),
        (1001, 1001001, "First Listing"),
        (1001, 1001002, "Re-Listing"),
        (1001, 1001003, "Recovered"),
        (1002, 1002001, "First Listing"),  # House with dual context (RENT + SALE)
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_configuration_service():
    """Mock the configuration service via the base class."""
    with patch(
        "bietlejuice.base.spark.base_core_model_spark_job.BaseCoreModelSparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = lambda key: {
            "merge_on": ["sk_core_listing"],
            "when_matched_update_condition": "source.ts_updated > target.ts_updated",
            "z_order_by": ["id_house_listing", "business_context"],
            "partitions": ["year", "month", "day"],
            "LISTING_BUSINESS_CONTEXT_TABLE": "test.listing_business_context",
            "HOUSE_TABLE": "test.house",
            "AUX_LBC_STATUS_VERSION_ORDER_TABLE": "test.aux_lbc_status_version_order",
            "AUX_HOUSE_LISTING_CATEGORY_TABLE": "test.aux_house_listing_category",
            "ENTITY_TYPE": "LISTING",
        }.get(key)
        yield mock_get_config


@pytest.fixture
def mock_surrogate_keys_helper():
    """Mock the SurrogateKeysHelper class."""
    with patch(
        "dags.core.core_listing.spark_jobs.load_core_listing.SurrogateKeysHelper"
    ) as mock_helper:

        def generate_surrogate_key(df, entity_type, id_column="id_listing"):
            # Add a mock surrogate key column for testing
            return df.withColumn("surrogate_key", df["id_listing"].cast(StringType()))

        mock_helper.generate_surrogate_key.side_effect = generate_surrogate_key
        yield mock_helper


@pytest.fixture
def core_listing_job(mock_configuration_service):
    """Create a CoreListingSparkJob instance with mocked configuration."""
    return CoreListingSparkJob()


@pytest.fixture
def sale_listings_df(core_listing_job, listing_business_context_df, house_df):
    """Process SALE listings DataFrame."""
    return core_listing_job._process_sale_listings(
        listing_business_context_df, house_df
    )


@pytest.fixture
def rent_listings_df(
    core_listing_job,
    listing_business_context_df,
    house_df,
    aux_lbc_status_version_order_df,
    aux_house_listing_category_df,
):
    """Process RENT listings DataFrame."""
    return core_listing_job._process_rent_listings(
        listing_business_context_df,
        house_df,
        aux_lbc_status_version_order_df,
        aux_house_listing_category_df,
    )


@pytest.fixture
def core_model_df(
    spark_session,
    core_listing_job,
    listing_business_context_df,
    house_df,
    aux_lbc_status_version_order_df,
    aux_house_listing_category_df,
    mock_surrogate_keys_helper,
):
    """Execute create_core_model and return the result DataFrame."""
    mock_read = Mock()

    def side_effect(table_name):
        if "listing_business_context" in table_name:
            return listing_business_context_df
        elif "house" in table_name and "listing" not in table_name:
            return house_df
        elif "lbc_status_version_order" in table_name:
            return aux_lbc_status_version_order_df
        elif "house_listing_category" in table_name:
            return aux_house_listing_category_df
        else:
            raise ValueError(f"Unknown table: {table_name}")

    mock_read.table.side_effect = side_effect

    with patch.object(
        type(spark_session), "read", new_callable=lambda: mock_read, create=True
    ):
        return core_listing_job.create_core_model(spark_session, None)
