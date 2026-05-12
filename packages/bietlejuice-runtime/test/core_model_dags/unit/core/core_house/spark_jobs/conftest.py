"""
Pytest fixtures for core_house Spark job tests.
"""

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

from dags.core.core_house.spark_jobs.load_core_house import CoreHouseSparkJob


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreHouseTest")
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
            StructField("id_user", LongType(), True),
            StructField("id_region", LongType(), True),
            StructField("id_external", StringType(), True),
            StructField("id_user_registrant", LongType(), True),
            StructField("address", StringType(), True),
            StructField("number", StringType(), True),
            StructField("neighborhood", StringType(), True),
            StructField("complement", StringType(), True),
            StructField("zipcode", StringType(), True),
            StructField("city", StringType(), True),
            StructField("total_area", IntegerType(), True),
            StructField("lat", DecimalType(10, 7), True),
            StructField("lng", DecimalType(10, 7), True),
            StructField("type", StringType(), True),
            StructField("bathrooms", IntegerType(), True),
            StructField("bedrooms", IntegerType(), True),
            StructField("suites", IntegerType(), True),
            StructField("floor", IntegerType(), True),
            StructField("dt_creation", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
        ]
    )

    data = [
        # House 1001 - Normal house with updates
        (
            1001,  # id
            101,  # id_user
            1,  # id_region
            "EXT-1001",  # id_external
            501,  # id_user_registrant
            "Rua das Flores",  # address
            "123",  # number
            "Centro",  # neighborhood
            "Apt 101",  # complement
            "01310-100",  # zipcode
            "São Paulo",  # city
            85,  # total_area
            Decimal("-23.5505840"),  # lat
            Decimal("-46.6333482"),  # lng
            "Apartamento",  # type
            2,  # bathrooms
            3,  # bedrooms
            1,  # suites
            5,  # floor
            datetime(2020, 3, 15, 10, 0),  # dt_creation
            datetime(2024, 7, 10, 14, 30),  # ts_updated
            datetime(2024, 7, 10, 14, 30),  # ts_database_transaction
        ),
        # House 1002 - House with owner from house_listing_relation
        (
            1002,  # id
            102,  # id_user
            1,  # id_region
            "EXT-1002",  # id_external
            502,  # id_user_registrant
            "Av. Paulista",  # address
            "1000",  # number
            "Bela Vista",  # neighborhood
            None,  # complement
            "01310-200",  # zipcode
            "São Paulo",  # city
            120,  # total_area
            Decimal("-23.5614730"),  # lat
            Decimal("-46.6560826"),  # lng
            "Apartamento",  # type
            3,  # bathrooms
            4,  # bedrooms
            2,  # suites
            10,  # floor
            datetime(2021, 6, 20, 9, 0),  # dt_creation
            datetime(2024, 8, 15, 11, 0),  # ts_updated
            datetime(2024, 8, 15, 11, 0),  # ts_database_transaction
        ),
        # House 1003 - House without owner in house_listing_relation (uses id_user fallback)
        (
            1003,  # id
            103,  # id_user
            2,  # id_region
            "EXT-1003",  # id_external
            503,  # id_user_registrant
            "Rua Oscar Freire",  # address
            "500",  # number
            "Jardins",  # neighborhood
            "Casa 2",  # complement
            "01426-001",  # zipcode
            "São Paulo",  # city
            200,  # total_area
            Decimal("-23.5616176"),  # lat
            Decimal("-46.6710331"),  # lng
            "Casa",  # type
            4,  # bathrooms
            5,  # bedrooms
            3,  # suites
            0,  # floor (ground floor for house)
            datetime(2022, 1, 10, 8, 0),  # dt_creation
            datetime(2024, 5, 20, 16, 0),  # ts_updated
            datetime(2024, 5, 20, 16, 0),  # ts_database_transaction
        ),
        # House 1004 - Legacy house that should be filtered out (created <= 2015, ts_updated is NULL)
        (
            1004,  # id
            104,  # id_user
            1,  # id_region
            "EXT-1004",  # id_external
            504,  # id_user_registrant
            "Rua Antiga",  # address
            "10",  # number
            "Centro",  # neighborhood
            None,  # complement
            "01000-000",  # zipcode
            "São Paulo",  # city
            50,  # total_area
            Decimal("-23.5500091"),  # lat
            Decimal("-46.6300338"),  # lng
            "CasaCondominio",  # type
            1,  # bathrooms
            1,  # bedrooms
            0,  # suites
            2,  # floor
            datetime(2015, 6, 1, 10, 0),  # dt_creation (year <= 2015)
            None,  # ts_updated (NULL)
            datetime(2015, 6, 1, 10, 0),  # ts_database_transaction
        ),
        # House 1005 - Old house but with updates (should NOT be filtered out)
        (
            1005,  # id
            105,  # id_user
            3,  # id_region
            "EXT-1005",  # id_external
            505,  # id_user_registrant
            "Rua Velha",  # address
            "20",  # number
            "Centro",  # neighborhood
            None,  # complement
            "01000-001",  # zipcode
            "São Paulo",  # city
            60,  # total_area
            Decimal("-23.5510577"),  # lat
            Decimal("-46.6310273"),  # lng
            "StudioOuKitchenette",  # type
            1,  # bathrooms
            1,  # bedrooms
            0,  # suites
            3,  # floor
            datetime(2014, 3, 1, 10, 0),  # dt_creation (year <= 2015)
            datetime(2024, 1, 15, 10, 0),  # ts_updated (NOT NULL)
            datetime(2024, 1, 15, 10, 0),  # ts_database_transaction
        ),
        # House 1006 - House NOT updated in July, but HLR updated in July
        (
            1006,  # id
            106,  # id_user
            1,  # id_region
            "EXT-1006",  # id_external
            506,  # id_user_registrant
            "Rua Nova",  # address
            "200",  # number
            "Pinheiros",  # neighborhood
            None,  # complement
            "05422-000",  # zipcode
            "São Paulo",  # city
            90,  # total_area
            Decimal("-23.5670000"),  # lat
            Decimal("-46.6900000"),  # lng
            "Apartamento",  # type
            2,  # bathrooms
            2,  # bedrooms
            1,  # suites
            7,  # floor
            datetime(2023, 5, 10, 10, 0),  # dt_creation
            datetime(2024, 5, 15, 10, 0),  # ts_updated (May)
            datetime(
                2024, 5, 15, 10, 0
            ),  # ts_database_transaction (May - outside July)
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_listing_relation_df(spark_session):
    """Create a sample house_listing_relation DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_house", LongType(), True),
            StructField("id_related", LongType(), True),
            StructField("related_as", StringType(), True),
            StructField("source_type", StringType(), True),
            StructField("ts_updated", TimestampType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
        ]
    )

    data = [
        # House 1001 - Multiple relations, should pick latest PROPERTY_OWNER with MAIN_USER
        (
            1001,  # id_house
            201,  # id_related (different from house.id_user)
            "PROPERTY_OWNER",  # related_as
            "MAIN_USER",  # source_type
            datetime(2024, 5, 10, 10, 0),  # ts_updated (older)
            datetime(2024, 5, 10, 10, 0),  # ts_database_transaction
        ),
        (
            1001,  # id_house
            202,  # id_related (this should be selected as latest)
            "PROPERTY_OWNER",  # related_as
            "MAIN_USER",  # source_type
            datetime(2024, 7, 10, 14, 0),  # ts_updated (latest)
            datetime(2024, 7, 10, 14, 0),  # ts_database_transaction
        ),
        # House 1001 - PROPERTY_OWNER but not MAIN_USER (should be ignored)
        (
            1001,  # id_house
            888,  # id_related
            "PROPERTY_OWNER",  # related_as
            "SECONDARY_USER",  # source_type (not MAIN_USER)
            datetime(2024, 9, 1, 10, 0),  # ts_updated
            datetime(2024, 9, 1, 10, 0),  # ts_database_transaction
        ),
        # House 1002 - Single PROPERTY_OWNER relation
        (
            1002,  # id_house
            203,  # id_related
            "PROPERTY_OWNER",  # related_as
            "MAIN_USER",  # source_type
            datetime(2024, 8, 15, 10, 0),  # ts_updated
            datetime(2024, 8, 15, 10, 0),  # ts_database_transaction
        ),
        # House 1002 - Non-PROPERTY_OWNER relation (should be ignored)
        (
            1002,  # id_house
            999,  # id_related
            "TENANT",  # related_as (not PROPERTY_OWNER)
            "MAIN_USER",  # source_type
            datetime(2024, 8, 20, 10, 0),  # ts_updated
            datetime(2024, 8, 20, 10, 0),  # ts_database_transaction
        ),
        # House 1003 has no PROPERTY_OWNER with MAIN_USER (will use fallback to id_user)
        (
            1003,  # id_house
            999,  # id_related
            "PROPERTY_OWNER",  # related_as
            "PERSON_REF",  # source_type
            datetime(2024, 8, 23, 10, 0),  # ts_updated
            datetime(2024, 8, 23, 10, 0),  # ts_database_transaction
        ),
        # House 1005 has no PROPERTY_OWNER with MAIN_USER (will use fallback to id_user)
        (
            1005,  # id_house
            990,  # id_related
            "PROPERTY_OWNER",  # related_as
            "MAIN_USER",  # source_type
            datetime(2024, 1, 15, 10, 0),  # ts_updated
            datetime(2024, 1, 15, 10, 0),  # ts_database_transaction
        ),
        # House 1006 - HLR updated in July (House table was not updated in July)
        (
            1006,  # id_house
            206,  # id_related
            "PROPERTY_OWNER",  # related_as
            "MAIN_USER",  # source_type
            datetime(2024, 7, 20, 10, 0),  # ts_updated (July)
            datetime(2024, 7, 20, 10, 0),  # ts_database_transaction (July)
        ),
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
        # Users from house.id_user
        (101, "uuid-person-101"),
        (102, "uuid-person-102"),
        (103, "uuid-person-103"),
        (104, "uuid-person-104"),
        (105, "uuid-person-105"),
        (106, "uuid-person-106"),
        # Users from house_listing_relation.id_related
        (201, "uuid-person-201"),
        (202, "uuid-person-202"),
        (203, "uuid-person-203"),
        (206, "uuid-person-206"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_configuration_service():
    """Mock the configuration service via the base class."""
    with patch(
        "bietlejuice.base.spark.base_core_model_spark_job.BaseCoreModelSparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = lambda key: {
            "merge_on": ["sk_core_house"],
            "partitions": ["year", "month", "day"],
            "HOUSE_TABLE": "test.house",
            "HOUSE_LISTING_RELATION_TABLE": "test.house_listing_relation",
            "USER_TABLE": "test.user",
            "ENTITY_TYPE": "HOUSE",
        }.get(key)
        yield mock_get_config


@pytest.fixture
def mock_surrogate_keys_helper():
    """Mock the SurrogateKeysHelper class."""
    with patch(
        "dags.core.core_house.spark_jobs.load_core_house.SurrogateKeysHelper"
    ) as mock_helper:

        def generate_surrogate_key(df, entity_type, id_column="id_house"):
            # Add a mock surrogate key column for testing
            return df.withColumn("surrogate_key", df["id_house"].cast(StringType()))

        mock_helper.generate_surrogate_key.side_effect = generate_surrogate_key
        yield mock_helper


@pytest.fixture
def mock_args():
    """Create mock arguments for the Spark job."""
    args = Mock()
    args.load_start_date = None
    args.load_end_date = None
    return args


@pytest.fixture
def mock_args_incremental():
    """Create mock arguments for incremental load (July 2024)."""
    args = Mock()
    args.load_start_date = "2024-07-01"
    args.load_end_date = "2024-07-31"
    return args


@pytest.fixture
def core_house_job(mock_configuration_service):
    """Create a CoreHouseSparkJob instance with mocked configuration."""
    return CoreHouseSparkJob()


@pytest.fixture
def filtered_houses_df(core_house_job, house_df):
    """Get filtered houses DataFrame."""
    return core_house_job._get_filtered_houses(house_df)


@pytest.fixture
def latest_hlr_df(core_house_job, house_listing_relation_df):
    """Get latest house listing relation DataFrame."""
    return core_house_job._get_latest_house_listing_relation(house_listing_relation_df)


def _create_core_model_with_args(
    spark_session,
    core_house_job,
    house_df,
    house_listing_relation_df,
    user_df,
    mock_surrogate_keys_helper,
    args,
):
    """Helper to execute create_core_model with specific args."""
    mock_read = Mock()

    def side_effect(table_name):
        if table_name == "test.house":
            return house_df
        elif table_name == "test.house_listing_relation":
            return house_listing_relation_df
        elif table_name == "test.user":
            return user_df
        else:
            raise ValueError(f"Unknown table: {table_name}")

    mock_read.table.side_effect = side_effect

    with patch.object(
        type(spark_session), "read", new_callable=lambda: mock_read, create=True
    ):
        return core_house_job.create_core_model(spark_session, args)


@pytest.fixture
def core_model_df(
    spark_session,
    core_house_job,
    house_df,
    house_listing_relation_df,
    user_df,
    mock_surrogate_keys_helper,
    mock_args,
):
    """Execute create_core_model with full load and return the result DataFrame."""
    return _create_core_model_with_args(
        spark_session,
        core_house_job,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_surrogate_keys_helper,
        mock_args,
    )


@pytest.fixture
def core_model_incremental_july_df(
    spark_session,
    core_house_job,
    house_df,
    house_listing_relation_df,
    user_df,
    mock_surrogate_keys_helper,
    mock_args_incremental,
):
    """Execute create_core_model with incremental load (July 2024)."""
    return _create_core_model_with_args(
        spark_session,
        core_house_job,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_surrogate_keys_helper,
        mock_args_incremental,
    )
