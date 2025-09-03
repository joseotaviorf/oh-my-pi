"""
Pytest fixtures for core_visit Spark job tests.
"""

import pytest
from unittest.mock import patch
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    LongType,
    BooleanType,
    DateType,
)
from datetime import datetime, date


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreVisitTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def visit_df(spark_session):
    """Create a sample visit DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_house", LongType(), True),
            StructField("id_visitor", LongType(), True),
            StructField("id_agent", LongType(), True),
            StructField("code", StringType(), True),
            StructField("status", StringType(), True),
            StructField("computed_status", StringType(), True),
            StructField("type", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("is_fixed_agent", BooleanType(), True),
            StructField("dt_visit", DateType(), True),
            StructField("ts_visit", TimestampType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
        ]
    )

    data = [
        (
            1,  # id
            1001,  # id_house
            2001,  # id_visitor
            3001,  # id_agent
            "VISIT001",  # code
            "Scheduled",  # status
            "CONFIRMED",  # computed_status
            "STANDARD",  # type
            "RENT",  # business_context
            False,  # is_fixed_agent
            date(2025, 1, 15),  # dt_visit
            datetime(2025, 1, 15, 14, 0),  # ts_visit
            datetime(2025, 1, 1, 10, 0),  # ts_created
            datetime(2025, 1, 1, 11, 0),  # ts_updated
        ),
        (
            2,  # id
            1002,  # id_house
            2002,  # id_visitor
            3002,  # id_agent
            "VISIT002",  # code
            "Done",  # status
            "DONE",  # computed_status
            "STANDARD",  # type
            "SALE",  # business_context
            True,  # is_fixed_agent
            date(2025, 1, 16),  # dt_visit
            datetime(2025, 1, 16, 15, 0),  # ts_visit
            datetime(2025, 1, 2, 10, 0),  # ts_created
            datetime(2025, 1, 2, 11, 0),  # ts_updated
        ),
        (
            3,  # id
            1003,  # id_house
            2003,  # id_visitor
            None,  # id_agent (null)
            "VISIT003",  # code
            "Canceled",  # status
            "CANCELED",  # computed_status
            "STANDARD",  # type
            "RENT",  # business_context
            False,  # is_fixed_agent
            date(2025, 1, 17),  # dt_visit
            datetime(2025, 1, 17, 16, 0),  # ts_visit
            datetime(2025, 1, 3, 10, 0),  # ts_created
            datetime(2025, 1, 3, 11, 0),  # ts_updated
        ),
        (
            4,  # id
            1004,  # id_house
            2004,  # id_visitor
            3004,  # id_agent
            "VISIT004",  # code
            "Scheduled",  # status
            "REQUESTED",  # computed_status
            "STANDARD",  # type
            "RENT",  # business_context
            False,  # is_fixed_agent
            date(2022, 12, 25),  # dt_visit (old date for filtering test)
            datetime(2022, 12, 25, 10, 0),  # ts_visit
            datetime(2022, 12, 25, 9, 0),  # ts_created
            datetime(2022, 12, 25, 10, 0),  # ts_updated (old date for filtering test)
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def visit_status_log_df(spark_session):
    """Create a sample visit status log DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_visit", LongType(), True),
            StructField("event_type", StringType(), True),
            StructField("reason", StringType(), True),
            StructField("ts_created", TimestampType(), True),
        ]
    )

    data = [
        # Visit 1 events
        (1, "VISIT_REQUESTED", None, datetime(2025, 1, 1, 9, 0)),
        (1, "VISIT_CONFIRMED", None, datetime(2025, 1, 1, 10, 0)),
        # Visit 2 events
        (2, "VISIT_REQUESTED", None, datetime(2025, 1, 2, 9, 0)),
        (2, "VISIT_CONFIRMED", None, datetime(2025, 1, 2, 10, 0)),
        (2, "VISIT_DONE", None, datetime(2025, 1, 2, 11, 0)),
        # Visit 3 events (canceled)
        (3, "VISIT_REQUESTED", None, datetime(2025, 1, 3, 9, 0)),
        (3, "VISIT_CANCELED", "Owner not available", datetime(2025, 1, 3, 10, 0)),
        # Visit 4 events
        (4, "VISIT_REQUESTED", None, datetime(2022, 12, 25, 9, 0)),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_df(spark_session):
    """Create a sample house DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_user", LongType(), True),
            StructField("address", StringType(), True),
        ]
    )

    data = [
        (1001, 4001, "Rua A, 123"),
        (1002, 4002, "Rua B, 456"),
        (1003, 4003, "Rua C, 789"),
        (1004, 4004, "Rua D, 321"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_listing_relation_df(spark_session):
    """Create a sample house listing relation DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField(
                "id_related", StringType(), True
            ),  # Changed to StringType to support both IDs and UUIDs
            StructField("related_as", StringType(), True),
        ]
    )

    data = [
        (1001, "5001", "PROPERTY_OWNER"),  # Numeric ID as string
        (1002, "owner_uuid_2", "PROPERTY_OWNER"),  # UUID string
        (1003, "5003", "PROPERTY_OWNER"),  # Numeric ID as string
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def ebdb_user_df(spark_session):
    """Create a sample EBDB user DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("uuid_person", StringType(), True),
            StructField("name", StringType(), True),
            StructField("email", StringType(), True),
        ]
    )

    data = [
        (
            5001,
            "owner_uuid_1",
            "João Silva",
            "joao@email.com",
        ),  # id=5001 matches house_listing_relation id_related="5001"
        (
            5002,
            "owner_uuid_2",
            "Maria Santos",
            "maria@email.com",
        ),  # uuid_person matches house_listing_relation id_related="owner_uuid_2"
        (
            5003,
            "owner_uuid_3",
            "Pedro Costa",
            "pedro@email.com",
        ),  # id=5003 matches house_listing_relation id_related="5003"
        (
            5004,
            "owner_uuid_4",
            "Ana Oliveira",
            "ana@email.com",
        ),  # Additional user for testing
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_config():
    """Mock configuration for testing."""
    with patch("dags.core.core_visit.spark_jobs.load_core_visit.Config") as mock_config:
        mock_config.ENTITY_TYPE = "VISIT"
        mock_config.VISIT_TABLE = "test.visit"
        mock_config.VISIT_STATUS_LOG_TABLE = "test.visit_status_log"
        mock_config.HOUSE_TABLE = "test.house"
        mock_config.HOUSE_LISTING_RELATION_TABLE = "test.house_listing_relation"
        mock_config.EBDB_USER_TABLE = "test.ebdb_user"
        mock_config.MERGE_ON = ["sk_core_visit"]
        mock_config.WHEN_MATCHED_UPDATE_CONDITION = (
            "source.ts_updated > target.ts_updated"
        )
        mock_config.Z_ORDER_BY = ["id_house", "business_context"]
        mock_config.PARTITIONS = ["year", "month", "day"]
        yield mock_config


@pytest.fixture
def mock_configuration_service():
    """Mock the configuration service via the base class."""
    with patch(
        "bietlejuice.base.spark.base_core_model_spark_job.BaseCoreModelSparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = lambda key: {
            "merge_on": ["sk_core_visit"],
            "when_matched_update_condition": "source.ts_updated > target.ts_updated",
            "z_order_by": ["id_house", "business_context"],
            "partitions": ["year", "month", "day"],
            "VISIT_TABLE": "test.visit",
            "VISIT_STATUS_LOG_TABLE": "test.visit_status_log",
            "HOUSE_TABLE": "test.house",
            "HOUSE_LISTING_RELATION_TABLE": "test.house_listing_relation",
            "EBDB_USER_TABLE": "test.ebdb_user",
            "ENTITY_TYPE": "VISIT",
        }.get(key)
        yield mock_get_config


@pytest.fixture
def mock_surrogate_keys_helper():
    """Mock the SurrogateKeysHelper class."""
    with patch(
        "dags.core.core_visit.spark_jobs.load_core_visit.SurrogateKeysHelper"
    ) as mock_helper:

        def generate_surrogate_key(df, entity_type):
            # Add a mock surrogate key column for testing
            return df.withColumn("sk_entity", df["id_visit"].cast(StringType()))

        mock_helper.generate_surrogate_key.side_effect = generate_surrogate_key
        yield mock_helper


@pytest.fixture
def mock_date_partitioning_helper():
    """Mock date partitioning (not needed as it's done inline)."""
    # DatePartitioningHelper is not used anymore,
    # partitioning is done inline with year(), month(), dayofmonth()
    yield None
