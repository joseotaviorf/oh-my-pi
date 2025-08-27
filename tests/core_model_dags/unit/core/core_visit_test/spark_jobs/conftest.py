import pytest
from unittest.mock import Mock, patch
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    BooleanType,
    DateType,
)
from datetime import datetime, date


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("test_core_visit")
        .master("local[*]")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .getOrCreate()
    )

    yield spark

    spark.stop()


@pytest.fixture
def visit_df(spark_session):
    """Create a sample visit DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("id_visitor", StringType(), True),
            StructField("id_agent", StringType(), True),
            StructField("id_house", StringType(), True),
            StructField("business_context", StringType(), True),
            StructField("status", StringType(), True),
            StructField("computed_status", StringType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
            StructField("code", StringType(), True),
            StructField("slot", StringType(), True),
            StructField("behavior", StringType(), True),
            StructField("booking_type", StringType(), True),
            StructField("structured", BooleanType(), True),
            StructField("business_model", StringType(), True),
            StructField("is_fixed_agent", BooleanType(), True),
            StructField("ts_visit", TimestampType(), True),
            StructField("dt_request", DateType(), True),
            StructField("dt_confirmation_expiration", DateType(), True),
        ]
    )

    data = [
        (
            "visit_1",
            "visitor_1",
            "agent_1",
            "house_1",
            "FOR_RENT",
            "Confirmed",
            "CONFIRMED",
            datetime(2023, 1, 1, 10, 0),
            datetime(2023, 1, 1, 11, 0),
            "V001",
            "morning",
            "standard",
            "instant",
            True,
            "b2c",
            False,
            datetime(2023, 1, 2, 14, 0),
            date(2023, 1, 1),
            date(2023, 1, 3),
        ),
        (
            "visit_2",
            "visitor_2",
            "agent_2",
            "house_2",
            "FOR_SALE",
            "Done",
            "DONE",
            datetime(2023, 1, 2, 10, 0),
            datetime(2023, 1, 2, 11, 0),
            "V002",
            "afternoon",
            "premium",
            "scheduled",
            False,
            "b2b",
            True,
            datetime(2023, 1, 3, 15, 0),
            date(2023, 1, 2),
            date(2023, 1, 4),
        ),
        (
            "visit_3",
            "visitor_3",
            "agent_3",
            "house_3",
            "FOR_RENT",
            None,
            "CANCELED",
            datetime(2023, 1, 3, 10, 0),
            datetime(2023, 1, 3, 11, 0),
            "V003",
            "evening",
            "standard",
            "instant",
            True,
            "b2c",
            False,
            datetime(2023, 1, 4, 16, 0),
            date(2023, 1, 3),
            date(2023, 1, 5),
        ),
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def visit_status_log_df(spark_session):
    """Create a sample visit status log DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_visit", StringType(), True),
            StructField("id_schedule", StringType(), True),
            StructField("event_type", StringType(), True),
            StructField("author_user_role", StringType(), True),
            StructField("on_behalf_of", StringType(), True),
            StructField("reason", StringType(), True),
            StructField("ts_created", TimestampType(), True),
        ]
    )

    data = [
        (
            "visit_1",
            "schedule_1",
            "VISIT_CONFIRMED",
            "AGENT",
            None,
            None,
            datetime(2023, 1, 1, 12, 0),
        ),
        (
            "visit_1",
            "schedule_1",
            "VISIT_DONE",
            "AGENT",
            None,
            None,
            datetime(2023, 1, 2, 15, 0),
        ),
        (
            "visit_2",
            "schedule_2",
            "VISIT_CONFIRMED",
            "VISITOR",
            None,
            None,
            datetime(2023, 1, 2, 12, 0),
        ),
        (
            "visit_2",
            "schedule_2",
            "VISIT_DONE",
            "AGENT",
            None,
            None,
            datetime(2023, 1, 3, 16, 0),
        ),
        (
            "visit_3",
            "schedule_3",
            "VISIT_REQUEST_CANCELED",
            "VISITOR",
            None,
            "No longer interested",
            datetime(2023, 1, 3, 12, 0),
        ),
        (
            "visit_3",
            "schedule_3",
            "VISIT_CANCELED",
            "AGENT",
            "VISITOR",
            "Customer request",
            datetime(2023, 1, 3, 13, 0),
        ),
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_df(spark_session):
    """Create a sample house DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("id_user", StringType(), True),
            StructField("id_region", StringType(), True),
            StructField("address", StringType(), True),
            StructField("neighborhood", StringType(), True),
            StructField("number", StringType(), True),
            StructField("complement", StringType(), True),
            StructField("city", StringType(), True),
            StructField("zipcode", StringType(), True),
            StructField("is_for_rent", BooleanType(), True),
            StructField("is_for_sale", BooleanType(), True),
        ]
    )

    data = [
        (
            "house_1",
            "owner_1",
            "region_1",
            "Rua A",
            "Centro",
            "123",
            "Apt 1",
            "São Paulo",
            "01000-000",
            True,
            False,
        ),
        (
            "house_2",
            "owner_2",
            "region_2",
            "Rua B",
            "Vila Nova",
            "456",
            None,
            "Rio de Janeiro",
            "20000-000",
            False,
            True,
        ),
        (
            "house_3",
            "owner_3",
            "region_3",
            "Rua C",
            "Jardins",
            "789",
            "Casa",
            "Belo Horizonte",
            "30000-000",
            True,
            True,
        ),
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_config():
    """Mock configuration for testing."""
    with patch(
        "dags.core.core_visit_test.spark_jobs.load_core_visit.Config"
    ) as mock_config:
        mock_config.ENTITY_TYPE = "VISIT"
        mock_config.VISIT_TABLE = "test.visit"
        mock_config.VISIT_STATUS_LOG_TABLE = "test.visit_status_log"
        mock_config.HOUSE_TABLE = "test.house"
        mock_config.CONTRACT_TABLE = "test.contract"
        mock_config.MERGE_ON = ["id_entity"]
        mock_config.WHEN_MATCHED_UPDATE_CONDITION = (
            "source.ts_updated > target.ts_updated"
        )
        mock_config.Z_ORDER_BY = ["id_entity", "status", "ts_updated"]
        mock_config.PARTITIONS = ["year", "month", "day"]
        yield mock_config


@pytest.fixture
def mock_read_table_or_path():
    """Mock the read_table_or_path function."""
    with patch(
        "dags.core.core_visit_test.spark_jobs.load_core_visit.read_table_or_path"
    ) as mock_read:
        yield mock_read


@pytest.fixture
def mock_delta_loader():
    """Mock the DeltaLoader class."""
    with patch(
        "dags.core.core_visit_test.spark_jobs.load_core_visit.DeltaLoader"
    ) as mock_loader:
        yield mock_loader


@pytest.fixture
def mock_configuration_service():
    """Mock the ConfigurationService class."""
    with patch(
        "dags.core.core_visit_test.spark_jobs.load_core_visit.ConfigurationService"
    ) as mock_service:
        mock_instance = Mock()
        mock_service.return_value = mock_instance
        mock_instance.get_config.side_effect = lambda key: {
            "merge_on": ["id_entity"],
            "when_matched_update_condition": "source.ts_updated > target.ts_updated",
            "z_order_by": ["id_entity", "status", "ts_updated"],
            "partitions": ["year", "month", "day"],
            "VISIT_TABLE": "test.visit",
            "VISIT_STATUS_LOG_TABLE": "test.visit_status_log",
            "HOUSE_TABLE": "test.house",
            "ENTITY_TYPE": "VISIT",
            "CONTRACT_TABLE": "test.contract",
        }.get(key)
        yield mock_service


@pytest.fixture
def mock_logger():
    """Mock the logger."""
    with patch(
        "dags.core.core_visit_test.spark_jobs.load_core_visit.logger"
    ) as mock_logger:
        yield mock_logger


@pytest.fixture
def sample_args():
    """Sample command line arguments for testing."""
    args = Mock()
    args.environment = "forno"
    args.bucket = "test-bucket"
    args.dag_name = "core_visit_test"
    args.schema = "core"
    args.table_name = "visit"
    args.load_start_date = "2023-01-01"
    args.load_end_date = "2023-01-31"
    return args
