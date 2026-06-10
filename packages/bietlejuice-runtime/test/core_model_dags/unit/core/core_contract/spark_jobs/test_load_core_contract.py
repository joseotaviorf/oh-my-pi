"""
Unit tests for CoreContractSparkJob.
"""

from datetime import date, datetime
from unittest.mock import patch

import pytest
from pyspark.sql.types import (
    BooleanType,
    DateType,
    DoubleType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from dags.core.core_contract.spark_jobs.load_core_contract import CoreContractSparkJob


class TestCoreContractSparkJob:
    """Test cases for CoreContractSparkJob class."""

    @pytest.fixture
    def mock_tables_success(
        self, contract_df, house_df, house_listing_relation_df, ebdb_user_df
    ):
        """Create mock data for successful test scenarios."""
        return {
            "contract_df": contract_df,
            "house_df": house_df,
            "house_listing_relation_df": house_listing_relation_df,
            "user_df": ebdb_user_df,
        }

    @pytest.fixture
    def mock_tables_empty(self, empty_dataframe, spark_session):
        """Create empty mock data for edge case testing."""
        # Create empty DataFrames with correct schemas
        house_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_user", LongType(), True),
                StructField("address", StringType(), True),
            ]
        )

        house_listing_relation_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_related", StringType(), True),
                StructField("related_as", StringType(), True),
            ]
        )

        user_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("uuid_person", StringType(), True),
                StructField("name", StringType(), True),
                StructField("email", StringType(), True),
            ]
        )

        return {
            "contract_df": empty_dataframe,
            "house_df": spark_session.createDataFrame([], house_schema),
            "house_listing_relation_df": spark_session.createDataFrame(
                [], house_listing_relation_schema
            ),
            "user_df": spark_session.createDataFrame([], user_schema),
        }

    def test_create_core_model_success(
        self,
        spark_session,
        mock_tables_success,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test the end-to-end logic with full, mocked data."""
        # Arrange
        job = CoreContractSparkJob()

        # Mock the table loading methods
        with (
            patch.object(
                job,
                "_load_contract_data",
                return_value=mock_tables_success["contract_df"],
            ),
            patch.object(
                job, "_load_house_data", return_value=mock_tables_success["house_df"]
            ),
            patch.object(
                job,
                "_load_house_listing_relation_data",
                return_value=mock_tables_success["house_listing_relation_df"],
            ),
            patch.object(
                job, "_load_user_data", return_value=mock_tables_success["user_df"]
            ),
        ):
            # Create mock args
            class MockArgs:
                load_start_date = "2025-01-01"
                load_end_date = "2025-01-31"

            args = MockArgs()

            # Act
            result_df = job.create_core_model(spark_session, args)

            # Assert
            assert result_df is not None
            assert result_df.count() == 3

            # Check that all expected columns are present
            expected_columns = [
                "sk_core_contract",
                "id_contract",
                "id_house",
                "id_tenant",
                "id_owner",
                "id_proposal",
                "status",
                "rental_administrator",
                "paying_condo",
                "responsible_for_condo",
                "paying_iptu",
                "responsible_for_iptu",
                "signature_type",
                "status_closing",
                "is_relisting_enabled",
                "rent",
                "iptu",
                "rental_guarantee_installment",
                "rental_guarantee_value",
                "home_insurance_installment",
                "home_insurance_value",
                "first_rent_comission_fee",
                "tenant_service_fee",
                "dt_started",
                "dt_entered",
                "dt_termination",
                "ts_contract_expected_end",
                "ts_signed",
                "ts_expected_termination",
                "ts_minuta_approved",
                "ts_created",
                "ts_updated",
                "ts_load",
                "year",
                "month",
                "day",
            ]

            for col_name in expected_columns:
                assert col_name in result_df.columns

            # Check partitioning columns are added
            assert "year" in result_df.columns
            assert "month" in result_df.columns
            assert "day" in result_df.columns
            assert "ts_load" in result_df.columns

            # Check surrogate key is generated
            assert "sk_core_contract" in result_df.columns

            # Verify the data integrity
            result_data = result_df.collect()
            assert len(result_data) == 3

            # Check that the joins worked correctly
            first_row = result_data[0]
            assert first_row["id_contract"] == 618399
            assert first_row["id_house"] == 892788483
            assert first_row["id_tenant"] == 2342789
            assert first_row["id_owner"] == 37879
            assert first_row["rental_administrator"] == "QUINTOANDAR"
            assert first_row["status"] == "Cancelado"
            # Check string fields (not converted to boolean)
            assert first_row["paying_condo"] == "Inquilino"
            assert first_row["paying_iptu"] == "Proprietario"

    def test_create_core_model_empty_input(
        self,
        spark_session,
        mock_tables_empty,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test job execution when all source tables are empty."""
        # Arrange
        job = CoreContractSparkJob()

        # Mock the table loading methods to return empty DataFrames
        with (
            patch.object(
                job,
                "_load_contract_data",
                return_value=mock_tables_empty["contract_df"],
            ),
            patch.object(
                job, "_load_house_data", return_value=mock_tables_empty["house_df"]
            ),
            patch.object(
                job,
                "_load_house_listing_relation_data",
                return_value=mock_tables_empty["house_listing_relation_df"],
            ),
            patch.object(
                job, "_load_user_data", return_value=mock_tables_empty["user_df"]
            ),
        ):
            # Create mock args
            class MockArgs:
                load_start_date = "2025-01-01"
                load_end_date = "2025-01-31"

            args = MockArgs()

            # Act
            result_df = job.create_core_model(spark_session, args)

            # Assert
            assert result_df is not None
            assert result_df.count() == 0

            # Check that the correct final schema is maintained even with empty data
            expected_columns = [
                "sk_core_contract",
                "id_contract",
                "id_house",
                "id_tenant",
                "id_owner",
                "id_proposal",
                "status",
                "rental_administrator",
                "paying_condo",
                "responsible_for_condo",
                "paying_iptu",
                "responsible_for_iptu",
                "signature_type",
                "status_closing",
                "is_relisting_enabled",
                "rent",
                "iptu",
                "rental_guarantee_installment",
                "rental_guarantee_value",
                "home_insurance_installment",
                "home_insurance_value",
                "first_rent_comission_fee",
                "tenant_service_fee",
                "dt_started",
                "dt_entered",
                "dt_termination",
                "ts_contract_expected_end",
                "ts_signed",
                "ts_expected_termination",
                "ts_minuta_approved",
                "ts_created",
                "ts_updated",
                "ts_load",
                "year",
                "month",
                "day",
            ]

            for col_name in expected_columns:
                assert col_name in result_df.columns

    def test_create_core_model_date_filter(
        self, spark_session, mock_configuration_service
    ):
        """Test the date-based filtering logic in _load_contract_data."""
        # Arrange
        job = CoreContractSparkJob()

        # Create test contract data with different dates
        contract_schema = StructType(
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

        contract_data = [
            (
                1,
                1001,
                2001,
                3001,
                "Active",
                '{"rentalAdministrator": "QUINTOANDAR"}',
                "QuintoAndar",
                "Inquilino",
                "QuintoAndar",
                "Inquilino",
                "Eletronica",
                None,
                False,
                1000.0,
                50.0,
                1,
                None,
                1,
                None,
                1.0,
                None,
                None,
                date(2025, 1, 15),
                date(2025, 1, 15),
                date(2025, 12, 31),
                datetime(2025, 6, 15),
                datetime(2025, 1, 15, 10, 0),
                datetime(2025, 12, 31),
                datetime(2025, 1, 15, 9, 0),
                datetime(2025, 1, 15, 8, 0),
                datetime(2025, 1, 15, 11, 0),
                datetime(2025, 1, 15, 10, 0),  # ts_database_transaction - within range
            ),
            (
                2,
                1002,
                2002,
                3002,
                "Active",
                '{"rentalAdministrator": "QUINTOANDAR"}',
                "QuintoAndar",
                "Inquilino",
                "QuintoAndar",
                "Inquilino",
                "Eletronica",
                None,
                False,
                1000.0,
                50.0,
                1,
                None,
                1,
                None,
                1.0,
                None,
                None,
                date(2025, 1, 15),
                date(2025, 1, 15),
                date(2025, 12, 31),
                datetime(2025, 6, 15),
                datetime(2025, 1, 15, 10, 0),
                datetime(2025, 12, 31),
                datetime(2025, 1, 15, 9, 0),
                datetime(2025, 1, 15, 8, 0),
                datetime(2025, 1, 15, 11, 0),
                datetime(
                    2024, 12, 31, 10, 0
                ),  # ts_database_transaction - outside range
            ),
        ]

        contract_df = spark_session.createDataFrame(contract_data, contract_schema)

        # Mock spark.table to return our test data
        with patch.object(spark_session, "table", return_value=contract_df):
            # Create mock args with date range
            class MockArgs:
                load_start_date = "2025-01-01"
                load_end_date = "2025-01-31"

            args = MockArgs()

            # Act
            filtered_df = job._load_contract_data(
                spark_session, job.get_contract_config(), args
            )

            # Assert
            assert filtered_df.count() == 1  # Only one record should pass the filter

            # Verify the correct record is filtered
            result_data = filtered_df.collect()
            assert result_data[0]["id"] == 1
            assert result_data[0]["ts_database_transaction"] == datetime(
                2025, 1, 15, 10, 0
            )

    def test_create_core_model_owner_coalesce(
        self, spark_session, mock_configuration_service, mock_surrogate_keys_helper
    ):
        """Test the id_owner coalesce logic: coalesce(col("u.id"), col("h.id_user"))."""
        # Arrange
        job = CoreContractSparkJob()

        # Create test data where u.id is NULL but h.id_user is present
        contract_schema = StructType(
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

        contract_data = [
            (
                1,
                1001,
                2001,
                3001,
                "Active",
                '{"rentalAdministrator": "QUINTOANDAR"}',
                "QuintoAndar",
                "Inquilino",
                "QuintoAndar",
                "Inquilino",
                "Eletronica",
                None,
                False,
                1000.0,
                50.0,
                1,
                None,
                1,
                None,
                1.0,
                None,
                None,
                date(2025, 1, 15),
                date(2025, 1, 15),
                date(2025, 12, 31),
                datetime(2025, 6, 15),
                datetime(2025, 1, 15, 10, 0),
                datetime(2025, 12, 31),
                datetime(2025, 1, 15, 9, 0),
                datetime(2025, 1, 15, 8, 0),
                datetime(2025, 1, 15, 11, 0),
                datetime(2025, 1, 15, 10, 0),
            )
        ]

        contract_df = spark_session.createDataFrame(contract_data, contract_schema)

        # House data with id_user
        house_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_user", LongType(), True),
            ]
        )

        house_data = [(1001, 5001)]  # id, id_user

        house_df = spark_session.createDataFrame(house_data, house_schema)

        # House listing relation data
        house_listing_relation_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_related", StringType(), True),
                StructField("related_as", StringType(), True),
            ]
        )

        house_listing_relation_data = [(1001, "5001", "PROPERTY_OWNER")]

        house_listing_relation_df = spark_session.createDataFrame(
            house_listing_relation_data, house_listing_relation_schema
        )

        # User data with NULL id (to test coalesce)
        user_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("uuid_person", StringType(), True),
            ]
        )

        user_data = [(None, "owner_uuid_1")]  # id is NULL

        user_df = spark_session.createDataFrame(user_data, user_schema)

        # Mock the table loading methods
        with (
            patch.object(job, "_load_contract_data", return_value=contract_df),
            patch.object(job, "_load_house_data", return_value=house_df),
            patch.object(
                job,
                "_load_house_listing_relation_data",
                return_value=house_listing_relation_df,
            ),
            patch.object(job, "_load_user_data", return_value=user_df),
        ):
            # Create mock args
            class MockArgs:
                load_start_date = "2025-01-01"
                load_end_date = "2025-01-31"

            args = MockArgs()

            # Act
            result_df = job.create_core_model(spark_session, args)

            # Assert
            assert result_df.count() == 1

            result_data = result_df.collect()
            # Should use h.id_user (5001) since u.id is NULL
            assert result_data[0]["id_owner"] == 5001

    def test_create_core_model_rental_administrator_coalesce(
        self, spark_session, mock_configuration_service, mock_surrogate_keys_helper
    ):
        """Test the rental_administrator coalesce logic: get_json_object(contract_rent_model, '$.rentalAdministrator')."""
        # Arrange
        job = CoreContractSparkJob()

        # Create test data where contract_rent_model JSON has null rentalAdministrator
        contract_schema = StructType(
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

        contract_data = [
            (
                1,
                1001,
                2001,
                3001,
                "Active",
                '{"rentalAdministrator": null}',  # NULL rentalAdministrator
                "QuintoAndar",
                "Inquilino",
                "QuintoAndar",
                "Inquilino",
                "Eletronica",
                None,
                False,
                1000.0,
                50.0,
                1,
                None,
                1,
                None,
                1.0,
                None,
                None,
                date(2025, 1, 15),
                date(2025, 1, 15),
                date(2025, 12, 31),
                datetime(2025, 6, 15),
                datetime(2025, 1, 15, 10, 0),
                datetime(2025, 12, 31),
                datetime(2025, 1, 15, 9, 0),
                datetime(2025, 1, 15, 8, 0),
                datetime(2025, 1, 15, 11, 0),
                datetime(2025, 1, 15, 10, 0),
            )
        ]

        contract_df = spark_session.createDataFrame(contract_data, contract_schema)

        # Empty house data (not needed for this test)
        house_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_user", LongType(), True),
            ]
        )

        house_df = spark_session.createDataFrame([], house_schema)

        # Empty house listing relation data
        house_listing_relation_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_related", StringType(), True),
                StructField("related_as", StringType(), True),
            ]
        )

        house_listing_relation_df = spark_session.createDataFrame(
            [], house_listing_relation_schema
        )

        # Empty user data
        user_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("uuid_person", StringType(), True),
            ]
        )

        user_df = spark_session.createDataFrame([], user_schema)

        # Mock the table loading methods
        with (
            patch.object(job, "_load_contract_data", return_value=contract_df),
            patch.object(job, "_load_house_data", return_value=house_df),
            patch.object(
                job,
                "_load_house_listing_relation_data",
                return_value=house_listing_relation_df,
            ),
            patch.object(job, "_load_user_data", return_value=user_df),
        ):
            # Create mock args
            class MockArgs:
                load_start_date = "2025-01-01"
                load_end_date = "2025-01-31"

            args = MockArgs()

            # Act
            result_df = job.create_core_model(spark_session, args)

            # Assert
            assert result_df.count() == 1

            result_data = result_df.collect()
            # Should use default value "QUINTOANDAR" since rentalAdministrator is NULL
            assert result_data[0]["rental_administrator"] == "QUINTOANDAR"
