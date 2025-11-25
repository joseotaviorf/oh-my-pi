"""
Pytest fixtures for core_listing.aux__lbc_status_version_order tests.
"""

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    LongType,
    IntegerType,
)
from datetime import datetime


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreAuxLbcListingTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def listing_business_context_aud_df(spark_session):
    """Create a sample listing_business_context_aud DataFrame for testing RENT context."""
    schema = StructType(
        [
            StructField("id_house", LongType(), True),
            StructField("rev", IntegerType(), True),
            StructField("status", StringType(), True),
            StructField("status_reason", StringType(), True),
            StructField("suspension_reason", StringType(), True),
            StructField("business_context", StringType(), True),
        ]
    )

    data = [
        # House 1
        (1001, 1, "EDITING", None, None, "RENT"),
        (1001, 2, "PUBLISHED", None, None, "RENT"),
        (1001, 3, "UNPUBLISHED", None, None, "RENT"),
        (1001, 4, "PUBLISHED", None, None, "RENT"),  # After 84+ days
        (1001, 5, "SUSPENDED", "RENTED", None, "RENT"),
        (1001, 6, "PUBLISHED", "RELISTING_EARLY_DEMAND", None, "RENT"),  # Relisting
        (1001, 7, "SUSPENDED", "RENTED", None, "RENT"),  # Termination cancelled
        # House 2
        (1002, 8, "PUBLISHED", None, None, "RENT"),
        (1002, 9, "SUSPENDED", None, None, "RENT"),  # Not RENTED, should not trigger
        (1002, 10, "PUBLISHED", None, None, "RENT"),
        (1002, 11, "UNPUBLISHED", None, None, "RENT"),
        (
            1002,
            12,
            "PUBLISHED",
            None,
            None,
            "RENT",
        ),  # Less than 84 days, should not trigger
        # House 3
        (1003, 16, "PUBLISHED", None, None, "RENT"),
        (1003, 17, "SUSPENDED", "ContractDraft", None, "RENT"),
        (1003, 18, "SUSPENDED", "RENTED", None, "RENT"),
        (1003, 19, "PUBLISHED", None, None, "RENT"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def user_revision_entity_df(spark_session):
    """Create a sample user_revision_entity DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_user", LongType(), True),
            StructField(
                "ts_revision", LongType(), True
            ),  # Unix timestamp in milliseconds
            StructField("reason", StringType(), True),
        ]
    )

    # Timestamps in milliseconds (Unix timestamp * 1000)
    # The id field must match the rev field in listing_business_context_aud for the JOIN to work
    data = [
        # House 1 revisions (rev 1 to 7)
        (
            1,
            5001,
            int(datetime(2024, 1, 1, 0, 0, 0).timestamp() * 1000),
            None,
        ),  # editing
        (
            2,
            5001,
            int(datetime(2024, 1, 3, 0, 0, 0).timestamp() * 1000),
            "First publication",
        ),  # published
        (
            3,
            5001,
            int(datetime(2024, 2, 15, 0, 0, 0).timestamp() * 1000),
            None,
        ),  # unpub
        (
            4,
            5001,
            int(datetime(2024, 5, 15, 0, 0, 0).timestamp() * 1000),
            None,
        ),  # pub RECOV
        (
            5,
            5001,
            int(datetime(2024, 6, 1, 0, 0, 0).timestamp() * 1000),  # 88 days later
            "Republished",
        ),  # susp rent
        (
            6,
            5001,
            int(datetime(2025, 6, 10, 0, 0, 0).timestamp() * 1000),
            "Publication",
        ),  # pub relist
        (
            7,
            5001,
            int(datetime(2025, 6, 20, 0, 0, 0).timestamp() * 1000),
            "TERMINATION_CANCELED",
        ),
        # House 2 revisions (rev 8 to 12)
        (8, 5002, int(datetime(2024, 1, 3, 0, 0, 0).timestamp() * 1000), None),
        (9, 5002, int(datetime(2025, 6, 20, 0, 0, 0).timestamp() * 1000), "Rented"),
        (10, 5002, int(datetime(2025, 7, 13, 0, 0, 0).timestamp() * 1000), None),
        (11, 5001, int(datetime(2025, 7, 24, 0, 0, 0).timestamp() * 1000), None),
        (12, 5002, int(datetime(2025, 8, 15, 0, 0, 0).timestamp() * 1000), None),
        # House 3 revisions (rev 13 to 19)
        (13, 5003, int(datetime(2015, 1, 26, 0, 0, 0).timestamp() * 1000), None),
        (14, 5003, int(datetime(2015, 2, 5, 0, 0, 0).timestamp() * 1000), None),
        (15, 5003, int(datetime(2015, 3, 25, 0, 0, 0).timestamp() * 1000), None),
        (16, 5004, int(datetime(2020, 1, 14, 0, 0, 0).timestamp() * 1000), None),
        (17, 5004, int(datetime(2020, 3, 4, 0, 0, 0).timestamp() * 1000), None),
        (18, 5004, int(datetime(2020, 3, 4, 0, 0, 0).timestamp() * 1000), None),
        (19, 5004, int(datetime(2020, 9, 29, 0, 0, 0).timestamp() * 1000), None),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def aux__house_status_version_order_df(spark_session):
    """Create a sample aux__house_status_version_order DataFrame for historical data.

    This represents data before listing_business_context was created (before 2020-01-06).
    For testing purposes, we'll create an empty DataFrame since most tests focus on LBC data.
    """
    schema = StructType(
        [
            StructField("id_house", LongType(), True),
            StructField("order_status", IntegerType(), True),
            StructField("order_version", IntegerType(), True),
            StructField("rev", IntegerType(), True),
            StructField("status_history", StringType(), True),
            StructField("reason", StringType(), True),
            StructField("events_change_status", StringType(), True),
            StructField("ts_first_publication", TimestampType(), True),
            StructField("ts_status_changed", TimestampType(), True),
            StructField("ts_status_changed_next", TimestampType(), True),
        ]
    )

    data = [
        (
            1003,
            1,
            1,
            13,
            None,
            None,
            None,
            datetime(2013, 8, 28, 19, 58, 26),
            datetime(2015, 1, 26, 0, 0, 0),
            datetime(2015, 2, 5, 0, 0, 0),
        ),
        (
            1003,
            2,
            1,
            14,
            "publicado",
            None,
            None,
            datetime(2013, 8, 28, 19, 58, 26),
            datetime(2015, 2, 5, 0, 0, 0),
            datetime(2015, 3, 25, 0, 0, 0),
        ),
        (
            1003,
            3,
            1,
            15,
            "alugado",
            None,
            "alugado",
            datetime(2013, 8, 28, 19, 58, 26),
            datetime(2015, 3, 25, 0, 0, 0),
            datetime(2020, 1, 14, 0, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def setup_temp_views(
    spark_session,
    listing_business_context_aud_df,
    user_revision_entity_df,
    aux__house_status_version_order_df,
):
    """Register DataFrames as temporary views for SQL queries."""
    listing_business_context_aud_df.createOrReplaceTempView(
        "listing_business_context_aud"
    )
    user_revision_entity_df.createOrReplaceTempView("user_revision_entity")
    aux__house_status_version_order_df.createOrReplaceTempView(
        "aux__house_status_version_order"
    )
    yield
    # Cleanup: drop temp views after test
    spark_session.catalog.dropTempView("listing_business_context_aud")
    spark_session.catalog.dropTempView("user_revision_entity")
    spark_session.catalog.dropTempView("aux__house_status_version_order")


@pytest.fixture
def aux__lbc_status_version_order_query():
    """Load and prepare the core_aux_listing SQL query for LBC."""
    query_path = (
        "dags/core/core_aux_listing/queries/core/aux__lbc_status_version_order.sql"
    )
    with open(query_path, "r") as f:
        query = f.read()

    # Replace QUALIFY clause with a subquery for PySpark 3.3.2 compatibility
    # QUALIFY is not fully supported in PySpark 3.3.2, so we replace it with a filtered subquery
    if "QUALIFY" in query:
        # Replace QUALIFY (in first_lbc_state)
        query = query.replace(
            """first_lbc_state AS (
    SELECT
        bch.id_house,
        bch.status,
        bch.status_reason,
        bch.ts_state_started,
        bch.ts_state_ended,
        DATEDIFF(bch.ts_state_ended, bch.ts_state_started) AS days_in_status
    FROM
        lbc_history AS bch
    WHERE
        bch.business_context = 'RENT'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC, bch.ts_state_ended ASC) = 1
),""",
            """first_lbc_state_aux AS (
    SELECT
        bch.id_house,
        bch.status,
        bch.status_reason,
        bch.ts_state_started,
        bch.ts_state_ended,
        DATEDIFF(bch.ts_state_ended, bch.ts_state_started) AS days_in_status,
        ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC, bch.ts_state_ended ASC) AS rn
    FROM
        lbc_history AS bch
    WHERE
        bch.business_context = 'RENT'
),
first_lbc_state AS (
    SELECT
        id_house,
        status,
        status_reason,
        ts_state_started,
        ts_state_ended,
        days_in_status
    FROM
        first_lbc_state_aux
    WHERE
        rn = 1
),""",
        )

    # Replace table names with temp views
    query = query.replace(
        "datalake_ebdb_clean.listing_business_context_aud",
        "listing_business_context_aud",
    )
    query = query.replace(
        "datalake_ebdb_clean.user_revision_entity", "user_revision_entity"
    )
    query = query.replace(
        "core_listing.aux__house_status_version_order",
        "aux__house_status_version_order",
    )

    return query


@pytest.fixture
def aux__lbc_status_version_order_result_df(
    spark_session, setup_temp_views, aux__lbc_status_version_order_query
):
    """Execute the core_aux_listing query and return the result DataFrame."""
    return spark_session.sql(aux__lbc_status_version_order_query)


@pytest.fixture
def aux__lbc_status_version_order_result_data(aux__lbc_status_version_order_result_df):
    """Return collected result data from the core_aux_listing query."""
    return aux__lbc_status_version_order_result_df.collect()
