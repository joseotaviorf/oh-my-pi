"""
Pytest fixtures for core_contract Spark job tests.
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
    DoubleType,
)
from datetime import datetime, date


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreContractTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def contract_df(spark_session):
    """Create a sample contract DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_house", LongType(), True),
            StructField("id_user", LongType(), True),
            StructField("id_proposal", LongType(), True),
            StructField("status", StringType(), True),
            StructField("contract_rent_model", StringType(), True),
            StructField("paying_condo", StringType(), True),
            StructField("responsible_for_condo", StringType(), True),
            StructField("paying_iptu", StringType(), True),
            StructField("responsible_for_iptu", StringType(), True),
            StructField("signature_type", StringType(), True),
            StructField("status_closing", StringType(), True),
            StructField("is_relisting_enabled", BooleanType(), True),
            StructField("rent", DoubleType(), True),
            StructField("iptu", DoubleType(), True),
            StructField("rental_guarantee_installment", LongType(), True),
            StructField("rental_guarantee_value", DoubleType(), True),
            StructField("home_insurance_installment", LongType(), True),
            StructField("home_insurance_value", DoubleType(), True),
            StructField("fist_rent_comission_fee", DoubleType(), True),
            StructField("tenant_service_fee", DoubleType(), True),
            StructField("agent_brokerage_share", DoubleType(), True),
            StructField("dt_started", DateType(), True),
            StructField("dt_entered", DateType(), True),
            StructField("dt_termination", DateType(), True),
            StructField("ts_contract_expected_end", TimestampType(), True),
            StructField("ts_signed", TimestampType(), True),
            StructField("ts_expected_termination", TimestampType(), True),
            StructField("ts_minuta_approved", TimestampType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
        ]
    )

    data = [
        (
            618399,  # id
            892776580,  # id_house
            66504,  # id_user
            1640,  # id_proposal
            "Finalizado",  # status
            '{"rentalAdministrator": "QUINTOANDAR"}',  # contract_rent_model
            "QuintoAndar",  # paying_condo
            "Inquilino",  # responsible_for_condo
            "QuintoAndar",  # paying_iptu
            "Inquilino",  # responsible_for_iptu
            "Eletronica",  # signature_type
            None,  # status_closing
            False,  # is_relisting_enabled
            2588.72,  # rent
            101.77,  # iptu
            1,  # rental_guarantee_installment
            None,  # rental_guarantee_value
            1,  # home_insurance_installment
            None,  # home_insurance_value
            1.0,  # fist_rent_comission_fee
            None,  # tenant_service_fee
            None,  # agent_brokerage_share
            date(2016, 2, 22),  # dt_started
            date(2016, 2, 22),  # dt_entered
            date(2019, 12, 4),  # dt_termination
            datetime(2018, 8, 22),  # ts_contract_expected_end
            datetime(2016, 2, 22, 12, 7, 7),  # ts_signed
            datetime(2019, 12, 4),  # ts_expected_termination
            datetime(2016, 2, 18, 14, 5, 36),  # ts_minuta_approved
            datetime(2016, 2, 18, 12, 52, 13),  # ts_created
            datetime(2019, 12, 4, 21, 43, 20),  # ts_updated
            datetime(2025, 1, 15, 10, 0, 0),  # ts_database_transaction
        ),
        (
            1894,  # id
            892785904,  # id_house
            58544,  # id_user
            3278,  # id_proposal
            "Finalizado",  # status
            '{"rentalAdministrator": "QUINTOANDAR"}',  # contract_rent_model
            "QuintoAndar",  # paying_condo
            "Inquilino",  # responsible_for_condo
            "QuintoAndar",  # paying_iptu
            "Inquilino",  # responsible_for_iptu
            "Eletronica",  # signature_type
            "ContratoAssinado",  # status_closing
            False,  # is_relisting_enabled
            1591.49,  # rent
            96.25,  # iptu
            1,  # rental_guarantee_installment
            None,  # rental_guarantee_value
            1,  # home_insurance_installment
            None,  # home_insurance_value
            1.0,  # fist_rent_comission_fee
            None,  # tenant_service_fee
            None,  # agent_brokerage_share
            date(2016, 7, 9),  # dt_started
            date(2016, 7, 9),  # dt_entered
            date(2019, 2, 2),  # dt_termination
            datetime(2019, 1, 9),  # ts_contract_expected_end
            datetime(2016, 7, 5, 20, 3, 0),  # ts_signed
            datetime(2019, 2, 2),  # ts_expected_termination
            datetime(2016, 7, 4, 18, 17, 32),  # ts_minuta_approved
            datetime(2016, 7, 4, 16, 41, 13),  # ts_created
            datetime(2019, 2, 4, 11, 50, 35),  # ts_updated
            datetime(2025, 1, 16, 10, 0, 0),  # ts_database_transaction
        ),
        (
            618399,  # id
            892788483,  # id_house
            2342789,  # id_user
            2350933,  # id_proposal
            "Cancelado",  # status
            '{"rentalAdministrator": "QUINTOANDAR"}',  # contract_rent_model
            "Inquilino",  # paying_condo
            "Inquilino",  # responsible_for_condo
            "Proprietario",  # paying_iptu
            "Inquilino",  # responsible_for_iptu
            "Eletronica",  # signature_type
            "ContratoEnviado",  # status_closing
            False,  # is_relisting_enabled
            2800.0,  # rent
            12.0,  # iptu
            1,  # rental_guarantee_installment
            None,  # rental_guarantee_value
            12,  # home_insurance_installment
            35.48,  # home_insurance_value
            0.0259,  # fist_rent_comission_fee
            0.2,  # tenant_service_fee
            0.2,  # agent_brokerage_share
            date(2023, 11, 7),  # dt_started
            date(2023, 11, 7),  # dt_entered
            None,  # dt_termination
            datetime(2026, 5, 7),  # ts_contract_expected_end
            None,  # ts_signed
            None,  # ts_expected_termination
            datetime(2023, 10, 23, 13, 41, 24),  # ts_minuta_approved
            datetime(2023, 10, 23, 13, 31, 15),  # ts_created
            datetime(2023, 10, 27, 12, 41, 33),  # ts_updated
            datetime(2025, 1, 17, 10, 0, 0),  # ts_database_transaction
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_df(spark_session):
    """Create a sample house DataFrame for testing based on real data."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_user", LongType(), True),
            StructField("address", StringType(), True),
        ]
    )

    data = [
        (892776580, 1551847, "Rua das Flores, 123"),  # id, id_user, address
        (892785904, 102554, "Rua das Palmeiras, 456"),  # id, id_user, address
        (892788483, 37879, "Rua das Acácias, 789"),  # id, id_user, address
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def house_listing_relation_df(spark_session):
    """Create a sample house listing relation DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_related", StringType(), True),
            StructField("related_as", StringType(), True),
        ]
    )

    data = [
        (892776580, "1551847", "PROPERTY_OWNER"),  # id, id_related, related_as
        (892785904, "102554", "PROPERTY_OWNER"),  # id, id_related, related_as
        (892788483, "37879", "PROPERTY_OWNER"),  # id, id_related, related_as
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
            1551847,
            "owner_uuid_1",
            "João Silva",
            "joao@email.com",
        ),  # id, uuid_person, name, email
        (
            102554,
            "owner_uuid_2",
            "Maria Santos",
            "maria@email.com",
        ),  # id, uuid_person, name, email
        (
            37879,
            "owner_uuid_3",
            "Pedro Costa",
            "pedro@email.com",
        ),  # id, uuid_person, name, email
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def empty_dataframe(spark_session):
    """Create an empty DataFrame with the contract schema for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_house", LongType(), True),
            StructField("id_user", LongType(), True),
            StructField("id_proposal", LongType(), True),
            StructField("status", StringType(), True),
            StructField("contract_rent_model", StringType(), True),
            StructField("paying_condo", StringType(), True),
            StructField("responsible_for_condo", StringType(), True),
            StructField("paying_iptu", StringType(), True),
            StructField("responsible_for_iptu", StringType(), True),
            StructField("signature_type", StringType(), True),
            StructField("status_closing", StringType(), True),
            StructField("is_relisting_enabled", BooleanType(), True),
            StructField("rent", DoubleType(), True),
            StructField("iptu", DoubleType(), True),
            StructField("rental_guarantee_installment", LongType(), True),
            StructField("rental_guarantee_value", DoubleType(), True),
            StructField("home_insurance_installment", LongType(), True),
            StructField("home_insurance_value", DoubleType(), True),
            StructField("fist_rent_comission_fee", DoubleType(), True),
            StructField("tenant_service_fee", DoubleType(), True),
            StructField("agent_brokerage_share", DoubleType(), True),
            StructField("dt_started", DateType(), True),
            StructField("dt_entered", DateType(), True),
            StructField("dt_termination", DateType(), True),
            StructField("ts_contract_expected_end", TimestampType(), True),
            StructField("ts_signed", TimestampType(), True),
            StructField("ts_expected_termination", TimestampType(), True),
            StructField("ts_minuta_approved", TimestampType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
        ]
    )
    return spark_session.createDataFrame([], schema)


@pytest.fixture
def mock_configuration_service():
    """Mock the configuration service via the base class."""
    with patch(
        "dags.core.core_contract.spark_jobs.load_core_contract.CoreContractSparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = lambda key: {
            "ENTITY_TYPE": "CONTRACT",
            "CONTRACT_TABLE": "test.contract",
            "HOUSE_TABLE": "test.house",
            "HOUSE_LISTING_RELATION_TABLE": "test.house_listing_relation",
            "EBDB_USER_TABLE": "test.ebdb_user",
        }.get(key)
        yield mock_get_config


@pytest.fixture
def mock_surrogate_keys_helper():
    """Mock the SurrogateKeysHelper class."""
    with patch(
        "dags.core.core_contract.spark_jobs.load_core_contract.SurrogateKeysHelper"
    ) as mock_helper:

        def generate_surrogate_key(df, entity_type, id_column="id_entity"):
            # Add a mock surrogate key column for testing
            return df.withColumn("surrogate_key", df["id_contract"].cast(StringType()))

        mock_helper.generate_surrogate_key.side_effect = generate_surrogate_key
        yield mock_helper
