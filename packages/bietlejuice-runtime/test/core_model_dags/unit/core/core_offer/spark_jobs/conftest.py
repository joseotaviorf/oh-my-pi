from datetime import datetime
from decimal import Decimal
from unittest.mock import Mock, patch

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    DecimalType,
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
        SparkSession.builder.appName("test_core_offer")
        .master("local[*]")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .getOrCreate()
    )

    yield spark

    spark.stop()


@pytest.fixture
def rental_transact_offer_df(spark_session):
    """Create a sample rental transact offer DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("uuid_offer", StringType(), True),
            StructField("id_tenant_external", StringType(), True),
            StructField("id_owner_external", StringType(), True),
            StructField("id_resident_info", LongType(), True),
            StructField("id_house_external", StringType(), True),
            StructField("id_firestore_offer", StringType(), True),
            StructField("status", StringType(), True),
            StructField("type", StringType(), True),
            StructField("turn", IntegerType(), True),
            StructField("iteration", IntegerType(), True),
            StructField("rejection_reason", StringType(), True),
            StructField("original_rent_value", DecimalType(10, 2), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
            StructField("ts_expiration", TimestampType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("op_cdc", StringType(), True),
        ]
    )

    data = [
        (
            1,
            "offer_uuid_1",
            "tenant_uuid_1",
            "owner_uuid_1",
            1001,
            "house_1",
            "firestore_1",
            "PENDING",
            "EXPRESS",
            1,
            1,
            None,
            Decimal("2500.00"),
            datetime(2025, 1, 1, 10, 0),
            datetime(2025, 1, 1, 11, 0),
            datetime(2025, 1, 15, 23, 59),
            datetime(2025, 1, 1, 12, 0),  # ts_database_transaction
            "i",  # insert
        ),
        (
            2,
            "offer_uuid_2",
            "tenant_uuid_2",
            "owner_uuid_2",
            1002,
            "house_2",
            "firestore_2",
            "ACCEPTED",
            "CUSTOM",
            2,
            1,
            None,
            Decimal("3000.00"),
            datetime(2025, 1, 2, 10, 0),
            datetime(2025, 1, 2, 11, 0),
            datetime(2025, 1, 16, 23, 59),
            datetime(2025, 1, 2, 12, 0),  # ts_database_transaction
            "u",  # update
        ),
        (
            3,
            "offer_uuid_3",
            "tenant_uuid_3",
            "owner_uuid_3",
            1003,
            "house_3",
            "firestore_3",
            "REJECTED",
            "EXPRESS",
            1,
            2,
            "Price too high",
            Decimal("2800.00"),
            datetime(2025, 1, 3, 10, 0),
            datetime(2025, 1, 3, 11, 0),
            datetime(2025, 1, 17, 23, 59),
            datetime(2025, 1, 3, 12, 0),  # ts_database_transaction
            "u",  # update
        ),
        (
            4,
            "offer_uuid_4",
            "tenant_uuid_4",
            "owner_uuid_4",
            1004,
            "house_4",
            "firestore_4",
            "EXPIRED",
            "CUSTOM",
            1,
            1,
            None,
            Decimal("2200.00"),
            datetime(2022, 12, 25, 10, 0),  # Before date range for testing
            datetime(2022, 12, 25, 11, 0),
            datetime(2025, 1, 10, 23, 59),
            datetime(
                2022, 12, 25, 12, 0
            ),  # ts_database_transaction - before date range
            "d",  # deleted - should be filtered out
        ),
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
        (101, "tenant_uuid_1", "João Silva", "joao@email.com"),
        (102, "owner_uuid_1", "Maria Santos", "maria@email.com"),
        (103, "tenant_uuid_2", "Pedro Oliveira", "pedro@email.com"),
        (104, "owner_uuid_2", "Ana Costa", "ana@email.com"),
        (105, "tenant_uuid_3", "Carlos Souza", "carlos@email.com"),
        (106, "owner_uuid_3", "Lucia Lima", "lucia@email.com"),
        # Note: No users for tenant_uuid_4 and owner_uuid_4 to test LEFT JOIN behavior
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_config():
    """Mock configuration for testing."""
    with patch("dags.core.core_offer.spark_jobs.load_core_offer.Config") as mock_config:
        mock_config.ENTITY_TYPE = "OFFER"
        mock_config.RENTAL_TRANSACT_OFFER_TABLE = "test.rental_transact_offer"
        mock_config.EBDB_USER_TABLE = "test.ebdb_user"
        mock_config.MERGE_ON = ["sk_core_offer"]
        mock_config.WHEN_MATCHED_UPDATE_CONDITION = (
            "source.ts_updated > target.ts_updated"
        )
        mock_config.Z_ORDER_BY = ["id_house", "status"]
        mock_config.PARTITIONS = ["year", "month", "day"]
        yield mock_config


@pytest.fixture
def mock_configuration_service():
    """Mock the ConfigurationService class."""
    with patch(
        "dags.core.core_offer.spark_jobs.load_core_offer.ConfigurationService"
    ) as mock_service:
        mock_instance = Mock()
        mock_service.return_value = mock_instance
        mock_instance.get_config.side_effect = lambda key: {
            "merge_on": ["sk_core_offer"],
            "when_matched_update_condition": "source.ts_updated > target.ts_updated",
            "z_order_by": ["id_house", "status"],
            "partitions": ["year", "month", "day"],
            "RENTAL_TRANSACT_OFFER_TABLE": "test.rental_transact_offer",
            "EBDB_USER_TABLE": "test.ebdb_user",
            "ENTITY_TYPE": "OFFER",
        }.get(key)
        yield mock_service


@pytest.fixture
def mock_logger():
    """Mock the logger."""
    with patch("dags.core.core_offer.spark_jobs.load_core_offer.logger") as mock_logger:
        yield mock_logger


@pytest.fixture
def sample_args():
    """Sample command line arguments for testing."""
    args = Mock()
    args.environment = "forno"
    args.bucket = "test-bucket"
    args.dag_name = "core_offer"
    args.schema = "core"
    args.table_name = "offer"
    args.load_start_date = "2023-01-01"
    args.load_end_date = "2023-01-31"
    args.extra_spark_job_arguments = "{}"
    args.table_privileges = None
    return args


@pytest.fixture
def sample_args_no_dates():
    """Sample command line arguments without date filtering for testing."""
    args = Mock()
    args.environment = "forno"
    args.bucket = "test-bucket"
    args.dag_name = "core_offer"
    args.schema = "core"
    args.table_name = "offer"
    args.load_start_date = None
    args.load_end_date = None
    args.extra_spark_job_arguments = "{}"
    args.table_privileges = None
    return args
