"""
Pytest fixtures for core_listing.aux__house_status_version_order tests.
"""

from datetime import datetime

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
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
        SparkSession.builder.appName("CoreAuxListingTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def house_aud_df(spark_session):
    """Create a sample house_aud DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_house", LongType(), True),
            StructField("rev", IntegerType(), True),
            StructField("status", StringType(), True),
            StructField("dt_first_publication", TimestampType(), True),
        ]
    )

    data = [
        # House 1: Beginning of the house's life, with its first publication
        (1001, 1, "edicao", None),
        (1001, 2, "publicado", datetime(2025, 1, 2, 0, 0, 0)),  # First version
        (1001, 3, "alugado", datetime(2025, 1, 2, 0, 0, 0)),
        # House 2: Unpublished for 84+ days
        (1002, 4, "publicado", datetime(2025, 1, 1, 0, 0, 0)),
        (1002, 5, "despublicado", datetime(2025, 1, 1, 0, 0, 0)),
        (
            1002,
            6,
            "publicado",
            datetime(2025, 1, 1, 0, 0, 0),
        ),  # Republished after 84+ days
        # House 3: Never published
        (1003, 7, "edicao", None),
        (1003, 8, "aguardando_publicacao", None),
        # House 4: Multiple publications and a suspension
        (1004, 9, "publicado", datetime(2025, 1, 1, 0, 0, 0)),
        (1004, 10, "despublicado", datetime(2025, 1, 1, 0, 0, 0)),
        (1004, 11, "publicado", datetime(2025, 1, 1, 0, 0, 0)),  # New version
        (1004, 12, "alugado", datetime(2025, 1, 1, 0, 0, 0)),
        (1004, 13, "publicado", datetime(2025, 1, 1, 0, 0, 0)),  # Another new version
        (1004, 14, "suspenso", datetime(2025, 1, 1, 0, 0, 0)),
        # House 5: Unpublished for less than 84 days (should NOT trigger version change)
        (1005, 15, "publicado", datetime(2025, 1, 1, 0, 0, 0)),
        (1005, 16, "despublicado", datetime(2025, 1, 1, 0, 0, 0)),
        (1005, 17, "publicado", datetime(2025, 1, 1, 0, 0, 0)),
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
    # The id field must match the rev field in house_aud for the JOIN to work
    data = [
        # House 1 revisions (rev = 1, 2, 3 in house_aud)
        (1, 5001, int(datetime(2025, 1, 1, 0, 0, 0).timestamp() * 1000), None),
        (
            2,
            5001,
            int(datetime(2025, 1, 2, 0, 0, 0).timestamp() * 1000),
            "Primeira publicação",
        ),
        (
            3,
            5001,
            int(datetime(2025, 1, 10, 0, 0, 0).timestamp() * 1000),
            "Imóvel alugado",
        ),
        # House 2 revisions (rev = 4, 5, 6 in house_aud)
        (4, 5002, int(datetime(2025, 1, 1, 0, 0, 0).timestamp() * 1000), "Publicação"),
        (
            5,
            5002,
            int(datetime(2025, 1, 3, 0, 0, 0).timestamp() * 1000),
            "Despublicado",
        ),
        (
            6,
            5002,
            int(datetime(2025, 3, 28, 0, 0, 0).timestamp() * 1000),
            "Republicacão",
        ),
        # House 3 revisions (rev = 7, 8 in house_aud)
        (7, 5003, int(datetime(2025, 1, 1, 0, 0, 0).timestamp() * 1000), None),
        (8, 5003, int(datetime(2025, 1, 2, 0, 0, 0).timestamp() * 1000), None),
        # House 4 revisions (rev = 9, 10, 11, 12, 13, 14 in house_aud)
        (9, 5004, int(datetime(2025, 1, 1, 0, 0, 0).timestamp() * 1000), "Publicação"),
        (
            10,
            5004,
            int(datetime(2025, 3, 6, 0, 0, 0).timestamp() * 1000),
            "Despublicado",
        ),
        (
            11,
            5004,
            int(datetime(2025, 6, 15, 0, 0, 0).timestamp() * 1000),
            "Republicacão",
        ),
        (
            12,
            5004,
            int(datetime(2025, 6, 28, 0, 0, 0).timestamp() * 1000),
            "[AUTO] Contrato 1234]",
        ),
        (
            13,
            5004,
            int(datetime(2025, 12, 12, 0, 0, 0).timestamp() * 1000),
            "Republicacão",
        ),
        (
            14,
            5004,
            int(datetime(2025, 12, 15, 0, 0, 0).timestamp() * 1000),
            "Suspenso pelo proprietário",
        ),
        # House 5 revisions (rev = 15, 16, 17 in house_aud) - unpublished for less than 84 days
        (15, 5005, int(datetime(2025, 1, 1, 0, 0, 0).timestamp() * 1000), "Publicação"),
        (
            16,
            5005,
            int(datetime(2025, 1, 10, 0, 0, 0).timestamp() * 1000),
            "Despublicado",
        ),
        (
            17,
            5005,
            int(datetime(2025, 1, 20, 0, 0, 0).timestamp() * 1000),
            "Republicado",
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def setup_temp_views(spark_session, house_aud_df, user_revision_entity_df):
    """Register DataFrames as temporary views for SQL queries."""
    house_aud_df.createOrReplaceTempView("house_aud")
    user_revision_entity_df.createOrReplaceTempView("user_revision_entity")
    yield
    # Cleanup: drop temp views after test
    spark_session.catalog.dropTempView("house_aud")
    spark_session.catalog.dropTempView("user_revision_entity")


@pytest.fixture
def aux__house_status_version_order_query():
    """Load and prepare the core_aux_listing SQL query."""
    query_path = (
        "dags/core/core_aux_listing/queries/core/aux__house_status_version_order.sql"
    )
    with open(query_path) as f:
        query = f.read()

    # Replace table names with temp views
    query = query.replace("datalake_ebdb_clean.house_aud", "house_aud")
    query = query.replace(
        "datalake_ebdb_clean.user_revision_entity", "user_revision_entity"
    )

    return query


@pytest.fixture
def aux__house_status_version_order_result_df(
    spark_session, setup_temp_views, aux__house_status_version_order_query
):
    """Execute the core_aux_listing query and return the result DataFrame."""
    return spark_session.sql(aux__house_status_version_order_query)


@pytest.fixture
def aux__house_status_version_order_result_data(
    aux__house_status_version_order_result_df,
):
    """Return collected result data from the core_aux_listing query."""
    return aux__house_status_version_order_result_df.collect()
