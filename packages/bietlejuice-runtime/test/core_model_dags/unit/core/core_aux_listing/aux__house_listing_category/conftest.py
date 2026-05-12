"""
Pytest fixtures for core_listing.aux__house_listing_category tests.
"""

from datetime import datetime

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


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreAuxHouseListingCategoryTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def aux__lbc_status_version_order_df(spark_session):
    """Create a sample aux__lbc_status_version_order DataFrame for testing.

    This represents the data that aux__house_listing_category depends on.
    """
    schema = StructType(
        [
            StructField("id_house", LongType(), True),
            StructField("lbc_state_order", IntegerType(), True),
            StructField("state_order", IntegerType(), True),
            StructField("days_in_status", IntegerType(), True),
            StructField("trigger_new_version", IntegerType(), True),
            StructField("listing_version", IntegerType(), True),
            StructField("rev", IntegerType(), True),
            StructField("status", StringType(), True),
            StructField("status_reason", StringType(), True),
            StructField("revision_reason", StringType(), True),
            StructField("is_extended_rental", BooleanType(), True),
            StructField("has_termination_canceled", BooleanType(), True),
            StructField("ts_state_started", TimestampType(), True),
            StructField("ts_state_ended", TimestampType(), True),
        ]
    )

    data = [
        # House 1 - Version 0 (category null)
        (
            1001,
            1,
            1,
            0,
            1,
            0,
            1,
            "EDITING",
            None,
            None,
            False,
            False,
            datetime(2024, 1, 1, 0, 0, 0),
            datetime(2024, 1, 3, 0, 0, 0),
        ),
        # House 1 - Version 1 (First Listing)
        (
            1001,
            2,
            2,
            6,
            0,
            1,
            2,
            "PUBLISHED",
            None,
            None,
            False,
            False,
            datetime(2024, 1, 3, 0, 0, 0),
            datetime(2024, 1, 9, 0, 0, 0),
        ),
        (
            1001,
            3,
            3,
            3,
            0,
            1,
            3,
            "SUSPENDED",
            None,
            None,
            False,
            False,
            datetime(2024, 1, 9, 0, 0, 0),
            datetime(2024, 1, 12, 0, 0, 0),
        ),
        # House 1 - Version 2 (Recovered)
        (
            1001,
            4,
            4,
            90,
            1,
            1,
            4,
            "UNPUBLISHED",
            None,
            None,
            False,
            False,
            datetime(2024, 1, 12, 0, 0, 0),
            datetime(2024, 4, 11, 0, 0, 0),
        ),
        (
            1001,
            5,
            5,
            30,
            0,
            2,
            5,
            "PUBLISHED",
            None,
            None,
            False,
            False,
            datetime(2024, 4, 11, 0, 0, 0),
            datetime(2024, 5, 11, 0, 0, 0),
        ),
        # House 1 - Version 3 (Re-Listing)
        (
            1001,
            6,
            6,
            374,
            1,
            2,
            6,
            "SUSPENDED",
            "RENTED",
            None,
            False,
            False,
            datetime(2024, 5, 11, 0, 0, 0),
            datetime(2025, 5, 20, 0, 0, 0),
        ),
        (
            1001,
            7,
            7,
            10,
            0,
            3,
            7,
            "PUBLISHED",
            "RELISTING_EARLY_DEMAND",
            "Publication",
            False,
            False,
            datetime(2025, 5, 20, 0, 0, 0),
            datetime(2025, 5, 30, 0, 0, 0),
        ),
        # House 2 - Version 1 (First Listing)
        (
            1002,
            1,
            1,
            30,
            0,
            1,
            8,
            "PUBLISHED",
            None,
            None,
            False,
            False,
            datetime(2024, 1, 3, 0, 0, 0),
            datetime(2024, 2, 2, 0, 0, 0),
        ),
        (
            1002,
            2,
            2,
            532,
            0,
            1,
            9,
            "SUSPENDED",
            "RENTED",
            None,
            False,
            False,
            datetime(2024, 2, 2, 0, 0, 0),
            datetime(2025, 7, 18, 0, 0, 0),
        ),
        (
            1002,
            3,
            3,
            90,
            0,
            1,
            10,
            "UNPUBLISHED",
            None,
            None,
            False,
            False,
            datetime(2025, 7, 18, 0, 0, 0),
            datetime(2025, 10, 16, 0, 0, 0),
        ),
        # House 2 - Version 1 (Re-Listing)
        (
            1002,
            4,
            4,
            27,
            0,
            2,
            11,
            "PUBLISHED",
            None,
            None,
            False,
            False,
            datetime(2025, 10, 16, 0, 0, 0),
            datetime(2025, 11, 12, 0, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def setup_temp_views(spark_session, aux__lbc_status_version_order_df):
    """Register DataFrames as temporary views for SQL queries."""
    aux__lbc_status_version_order_df.createOrReplaceTempView(
        "aux__lbc_status_version_order"
    )
    yield
    # Cleanup: drop temp views after test
    spark_session.catalog.dropTempView("aux__lbc_status_version_order")


@pytest.fixture
def aux__house_listing_category_query():
    """Load and prepare the core_aux_listing SQL query for house_listing_category."""
    query_path = (
        "dags/core/core_aux_listing/queries/core/aux__house_listing_category.sql"
    )
    with open(query_path) as f:
        query = f.read()

    # Replace FIRST() window function with FIRST_VALUE() for PySpark compatibility
    # FIRST() is not available in PySpark, but FIRST_VALUE() is
    query = query.replace(
        "FIRST(status) OVER(PARTITION BY id_house, listing_version ORDER BY rev DESC, ts_state_started DESC, ts_state_ended DESC) AS category_change,",
        "FIRST_VALUE(status) OVER(PARTITION BY id_house, listing_version ORDER BY rev DESC, ts_state_started DESC, ts_state_ended DESC) AS category_change,",
    )
    query = query.replace(
        "FIRST(status_reason) OVER(PARTITION BY id_house, listing_version ORDER BY rev DESC, ts_state_started DESC, ts_state_ended DESC) AS category_change_reason",
        "FIRST_VALUE(status_reason) OVER(PARTITION BY id_house, listing_version ORDER BY rev DESC, ts_state_started DESC, ts_state_ended DESC) AS category_change_reason",
    )

    # Replace LAST() aggregation function for PySpark compatibility with exact equivalence
    # LAST() in GROUP BY ALL gets the last value based on natural order (highest rev/ts_state_started)
    # To replicate this exactly, we need to:
    # 1. Add a calculated column in house_status_version_last_status CTE that gets days_in_status
    #    from the row with highest rev/ts_state_started using FIRST_VALUE with ORDER BY DESC
    # 2. Use that calculated column in the GROUP BY instead of LAST()

    # Step 1: Add the calculated column to house_status_version_last_status CTE
    # We'll add it right after the has_termination_canceled calculation
    query = query.replace(
        "MAX(ms_o.has_termination_canceled) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS has_termination_canceled",
        """MAX(ms_o.has_termination_canceled) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS has_termination_canceled,
        FIRST_VALUE(lbc_vo.days_in_status) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version ORDER BY lbc_vo.rev DESC, lbc_vo.ts_state_started DESC) AS last_days_in_status""",
    )

    # Step 2: Replace LAST() with the calculated column
    query = query.replace(
        "LAST(hs_v.days_in_status) AS days_in_status,",
        "MAX(hs_v.last_days_in_status) AS days_in_status,",
    )

    # Replace GROUP BY ALL with explicit non-aggregated columns
    # Only non-aggregated columns should be in GROUP BY
    query = query.replace(
        """GROUP BY
        ALL""",
        """GROUP BY
        hs_v.id_house,
        hs_v.listing_version,
        sc_v.category_change,
        sc_v.category_change_reason,
        hs_v.ts_last_unpublished,
        hs_v.is_extended_rental,
        hs_v.has_termination_canceled,
        hs_v.has_been_rented""",
    )

    # Replace table names with temp views
    query = query.replace(
        "core_listing.aux__lbc_status_version_order", "aux__lbc_status_version_order"
    )

    return query


@pytest.fixture
def aux__house_listing_category_result_df(
    spark_session, setup_temp_views, aux__house_listing_category_query
):
    """Execute the core_aux_listing query and return the result DataFrame."""
    return spark_session.sql(aux__house_listing_category_query)


@pytest.fixture
def aux__house_listing_category_result_data(aux__house_listing_category_result_df):
    """Return collected result data from the core_aux_listing query."""
    return aux__house_listing_category_result_df.collect()
