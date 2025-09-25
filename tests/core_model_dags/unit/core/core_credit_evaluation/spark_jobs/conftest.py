"""
Pytest fixtures for core_credit_evaluation Spark job tests.
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
    DecimalType,
    DoubleType,
)
from datetime import datetime
from decimal import Decimal


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreCreditEvaluationTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def credit_evaluation_df(spark_session):
    """Create a sample credit evaluation DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_house", LongType(), True),
            StructField("id_proposal", LongType(), True),
            StructField("id_user", LongType(), True),
            StructField("id_city", LongType(), True),
            StructField("id_group", LongType(), True),
            StructField("reason", StringType(), True),
            StructField("result", StringType(), True),
            StructField("early_result", StringType(), True),
            StructField("limit_value", DoubleType(), True),
            StructField("pre_approved_limit", DecimalType(10, 2), True),
            StructField("status", StringType(), True),
            StructField("type", StringType(), True),  # Source column name
            StructField("scope", StringType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
            StructField("ts_expires", TimestampType(), True),
        ]
    )

    data = [
        (
            1,  # id
            1001,  # id_house
            2001,  # id_proposal
            3001,  # id_user
            4001,  # id_city
            5001,  # id_group
            None,  # reason - NULL for positive approval (no negative reason)
            "PRE_APPROVED_WITH_GUARANTEE",  # result - positive result
            "APPROVED",  # early_result
            3500.0,  # limit_value
            Decimal("3000.00"),  # pre_approved_limit
            "FINISHED",  # status
            "REGULAR",  # type
            "HOUSE",  # scope
            datetime(2025, 1, 1, 10, 0),  # ts_created
            datetime(2025, 1, 1, 11, 0),  # ts_updated
            datetime(2025, 2, 1, 0, 0),  # ts_expires
        ),
        (
            2,  # id
            1002,  # id_house
            None,  # id_proposal (NULL - early credit case)
            3002,  # id_user
            4002,  # id_city
            None,  # id_group (NULL - early credit case)
            "INSUFFICIENT_INCOME",  # reason - negative reason
            "PRE_REJECTED",  # result - negative result
            None,  # early_result
            None,  # limit_value
            None,  # pre_approved_limit
            "FINISHED",  # status
            "LIGHT_APPROVAL",  # type
            "HOUSE",  # scope
            datetime(2025, 1, 2, 10, 0),  # ts_created
            datetime(2025, 1, 2, 11, 0),  # ts_updated
            datetime(2025, 2, 2, 0, 0),  # ts_expires
        ),
        (
            3,  # id
            None,  # id_house
            None,  # id_proposal
            3003,  # id_user
            4003,  # id_city
            None,  # id_group (NULL - credit passport case)
            None,  # reason - NULL for bypass (no negative reason)
            "BYPASSED",  # result (bypass case)
            "BYPASSED",  # early_result
            4000.0,  # limit_value (double)
            Decimal("4000.00"),  # pre_approved_limit
            "FINISHED",  # status
            "REGULAR",  # type
            "CITY",  # scope (credit passport case)
            datetime(2025, 1, 3, 10, 0),  # ts_created
            datetime(2025, 1, 3, 11, 0),  # ts_updated
            datetime(2025, 2, 3, 0, 0),  # ts_expires
        ),
        (
            4,  # id
            1004,  # id_house
            2004,  # id_proposal
            3004,  # id_user
            4004,  # id_city
            5005,  # id_group
            "BAD_SCORE",  # reason - negative reason
            "PRE_REJECTED",  # result - negative result (corrigido)
            None,  # early_result
            None,  # limit_value (NULL for rejected)
            None,  # pre_approved_limit (NULL for rejected)
            "FINISHED",  # status
            "REGULAR",  # type
            "HOUSE",  # scope
            datetime(2022, 12, 25, 10, 0),  # ts_created (old date for filtering test)
            datetime(2022, 12, 25, 11, 0),  # ts_updated (old date for filtering test)
            datetime(2023, 1, 25, 0, 0),  # ts_expires
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_config():
    """Mock configuration for testing."""
    with patch(
        "dags.core.core_credit_evaluation.spark_jobs.load_core_credit_evaluation.Config"
    ) as mock_config:
        mock_config.ENTITY_TYPE = "CREDIT_EVALUATION"
        mock_config.CREDIT_EVALUATION_TABLE = "test.credit_evaluation"
        mock_config.MERGE_ON = ["sk_core_credit_evaluation"]
        mock_config.WHEN_MATCHED_UPDATE_CONDITION = (
            "source.ts_updated > target.ts_updated"
        )
        mock_config.Z_ORDER_BY = ["id_proposal", "id_user", "status"]
        mock_config.PARTITIONS = ["year", "month", "day"]
        yield mock_config


@pytest.fixture
def house_df(spark_session):
    """Create a sample house DataFrame for testing."""
    schema = StructType(
        [StructField("id", LongType(), True), StructField("id_user", LongType(), True)]
    )

    data = [
        (1001, 7001),  # house_id, owner_user_id
        (1002, 7002),
        (1003, 7003),
        (1004, 7004),
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_listing_relation_df(spark_session):
    """Create a sample house_listing_relation DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_related", StringType(), True),  # Can be user ID or UUID
            StructField("related_as", StringType(), True),
        ]
    )

    data = [
        (1001, "8001", "PROPERTY_OWNER"),  # house_id, related_user_id, relation_type
        (1002, "uuid-8002", "PROPERTY_OWNER"),  # house_id, user_uuid, relation_type
        (1003, "8003", "PROPERTY_OWNER"),
        (1004, "uuid-8004", "PROPERTY_OWNER"),
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def user_df(spark_session):
    """Create a sample user DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("uuid_person", StringType(), True),
        ]
    )

    data = [
        (8001, "uuid-8001"),  # user_id, uuid
        (8002, "uuid-8002"),
        (8003, "uuid-8003"),
        (8004, "uuid-8004"),
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_configuration_service():
    """Mock the configuration service via the base class."""
    with patch(
        "bietlejuice.base.spark.base_core_model_spark_job.BaseCoreModelSparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = lambda key: {
            "merge_on": ["sk_core_credit_evaluation"],
            "when_matched_update_condition": "source.ts_updated > target.ts_updated",
            "z_order_by": ["id_proposal", "id_user", "status"],
            "partitions": ["year", "month", "day"],
            "CREDIT_EVALUATION_TABLE": "test.credit_evaluation",
            "HOUSE_TABLE": "test.house",
            "HOUSE_LISTING_RELATION_TABLE": "test.house_listing_relation",
            "EBDB_USER_TABLE": "test.user",
            "ENTITY_TYPE": "CREDIT_EVALUATION",
        }.get(key)
        yield mock_get_config


@pytest.fixture
def mock_surrogate_keys_helper():
    """Mock the SurrogateKeysHelper class."""
    with patch(
        "dags.core.core_credit_evaluation.spark_jobs.load_core_credit_evaluation.SurrogateKeysHelper"
    ) as mock_helper:

        def generate_surrogate_key(df, entity_type, id_column="id_credit_evaluation"):
            # Add a mock surrogate key column for testing
            return df.withColumn(
                "surrogate_key", df["id_credit_evaluation"].cast(StringType())
            )

        mock_helper.generate_surrogate_key.side_effect = generate_surrogate_key
        yield mock_helper


@pytest.fixture
def sample_args():
    """Sample command line arguments for testing."""
    from argparse import Namespace

    args = Namespace()
    args.load_start_date = None
    args.load_end_date = None
    return args


@pytest.fixture
def sample_args_with_dates():
    """Sample command line arguments with date filtering for testing."""
    from argparse import Namespace

    args = Namespace()
    args.load_start_date = "2025-01-01"
    args.load_end_date = "2025-01-31"
    return args


@pytest.fixture
def comprehensive_reason_values():
    """Comprehensive list of reason values used in production."""
    return {
        # Positive cases typically have NULL reason (no rejection reason needed)
        "positive": [None],  # Most positive approvals don't need a specific reason
        # Negative reasons - explaining why the evaluation was rejected
        "negative": [
            "INSUFFICIENT_INCOME",
            "BAD_SCORE",
            "BLOCKLIST",
            "INSTABLE_INCOME",
            "NO_SCORE",
            "SERASA_SCORE_BLOCKED",
            "PENDING_INVOICES",
            "CLEAR_NO",
        ],
    }


@pytest.fixture
def comprehensive_result_values():
    """Comprehensive list of result values used in production."""
    return {
        # Positive results
        "positive": [
            "REGULAR",
            "PRE_APPROVED",
            "PRE_APPROVED_WITH_GUARANTEE",
            "BYPASSED",
        ],
        # Negative results
        "negative": ["PRE_REJECTED"],
    }
