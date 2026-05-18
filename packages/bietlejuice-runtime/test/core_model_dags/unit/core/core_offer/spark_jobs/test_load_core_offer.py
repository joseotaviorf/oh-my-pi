import importlib.util

# Import the actual functions from the DAG
import sys
from pathlib import Path
from unittest.mock import Mock, patch

import pytest
from pyspark.sql import DataFrame
from pyspark.sql.functions import col, lit


def _find_project_root() -> Path:
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    raise RuntimeError("Could not locate project root from test path")


project_root = _find_project_root()
load_core_offer_path = (
    project_root / "dags" / "core" / "core_offer" / "spark_jobs" / "load_core_offer.py"
)

# Add project root to Python path
sys.path.insert(0, str(project_root))

# Mock problematic dependencies before importing
mock_services = Mock()


# Create a mock base class that can be inherited from
class MockBaseCoreModelSparkJob:
    def __init__(self, job_name):
        self.job_name = job_name
        self.logger = Mock()
        self.config_service = None

    def parse_args(self):
        mock_args = Mock()
        mock_args.environment = "forno"
        mock_args.bucket = "test-bucket"
        mock_args.dag_name = "core_offer"
        mock_args.schema = "core"
        mock_args.table_name = "offer"
        mock_args.load_start_date = "2025-01-01"
        mock_args.load_end_date = "2025-01-31"
        mock_args.extra_spark_job_arguments = "{}"
        mock_args.table_privileges = None
        return mock_args

    def initialize_configuration(self, source):
        pass

    def get_config(self, key, required=True, default=None):
        config_map = {
            "ENTITY_TYPE": "OFFER",
            "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
            "EBDB_USER_TABLE": "test_ebdb_user_table",
        }
        return config_map.get(key, default)

    def initialize_spark_session(self):
        return Mock()

    def setup_table_privileges(self, args):
        return Mock()

    def run_pipeline(self, dataframe, args, spark):
        pass

    def run(self):
        pass


with patch.dict(
    "sys.modules",
    {
        "quintoandar_logger": Mock(),
        "hierarchical_conf.hierarchical_conf": Mock(),
        "bietlejuice": Mock(),
        "bietlejuice.base": Mock(),
        "bietlejuice.base.pipeline": Mock(),
        "bietlejuice.base.spark": Mock(),
        "bietlejuice.base.spark.base_spark": Mock(),
        "bietlejuice.base.spark.base_core_model_spark_job": type(
            "MockModule", (), {"BaseCoreModelSparkJob": MockBaseCoreModelSparkJob}
        )(),
        "bietlejuice.base.spark.unity_catalog_helper": Mock(),
        "bietlejuice.base.databricks": Mock(),
        "bietlejuice.base.databricks.table_privileges": Mock(),
        "bietlejuice.base.core_models": Mock(),
        "bietlejuice.base.core_models.helpers": Mock(),
        "bietlejuice.base.core_models.helpers.surrogate_keys": Mock(),
        "bietlejuice.services": mock_services,
        "bietlejuice.services.configuration_service": Mock(),
        "bietlejuice.services.metastore_services": Mock(),
        "bietlejuice.services.metastore_services.spark_metastore_service": Mock(),
        "bietlejuice.loaders": Mock(),
        "bietlejuice.loaders.delta_loader": Mock(),
        "bietlejuice.pipeline": Mock(),
        "bietlejuice.pipeline.abstract_pipeline": Mock(),
        "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline": Mock(),
        "bietlejuice.clients": Mock(),
        "bietlejuice.clients.db_clients": Mock(),
        "bietlejuice.consumers": Mock(),
        "bietlejuice.consumers.db_consumers": Mock(),
        "bietlejuice.consumers.db_consumers.databricks_consumer": Mock(),
    },
):
    # Load the module dynamically
    spec = importlib.util.spec_from_file_location(
        "load_core_offer", load_core_offer_path
    )
    load_core_offer = importlib.util.module_from_spec(spec)
    sys.modules["load_core_offer"] = load_core_offer
    spec.loader.exec_module(load_core_offer)

# Import the functions we need to test
CoreOfferSparkJob = load_core_offer.CoreOfferSparkJob
JOB_NAME = load_core_offer.JOB_NAME


class TestCoreOfferSparkJob:
    """Test cases for CoreOfferSparkJob class - isolated to this DAG context."""

    def test_core_offer_spark_job_initialization(self):
        """Test CoreOfferSparkJob can be initialized."""
        # Act & Assert - Should not raise an exception
        job = CoreOfferSparkJob()
        assert job.job_name == "core_offer"

    def test_core_offer_spark_job_has_required_methods(self):
        """Test CoreOfferSparkJob has all required methods."""
        job = CoreOfferSparkJob()
        # Assert
        assert hasattr(job, "get_offer_config")
        assert hasattr(job, "create_core_model")
        assert hasattr(job, "run")
        assert hasattr(job, "parse_args")
        assert hasattr(job, "initialize_spark_session")

    def test_get_offer_config_returns_correct_structure(self):
        """Test get_offer_config returns the expected configuration structure."""
        # Arrange
        job = CoreOfferSparkJob()

        # Mock the get_config method
        with patch.object(job, "get_config") as mock_get_config:
            mock_get_config.side_effect = lambda key: {
                "ENTITY_TYPE": "OFFER",
                "RENTAL_TRANSACT_OFFER_TABLE": "test.rental_transact_offer",
                "EBDB_USER_TABLE": "test.ebdb_user",
            }[key]

            # Act
            config = job.get_offer_config()

            # Assert
            assert "ENTITY_TYPE" in config
            assert "RENTAL_TRANSACT_OFFER_TABLE" in config
            assert "EBDB_USER_TABLE" in config
            assert len(config) == 3  # Only 3 configs after removing EBDB_OFFER_TABLE


class TestCreateOfferCoreModel:
    """Test cases for create_core_model method - isolated to this DAG context."""

    def test_create_core_model_basic_flow(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test create_core_model orchestrates the full flow correctly."""
        # Mock the functions within the loaded module
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            # Arrange
            job = CoreOfferSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = None  # Set explicit None values
            mock_args.load_end_date = None
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            # Mock the withColumn chain for year, month, day columns
            mock_result_with_date_cols = Mock(spec=DataFrame)
            mock_result_with_date_cols.count.return_value = 3
            mock_result_df.withColumn.return_value = mock_result_with_date_cols
            mock_result_with_date_cols.withColumn.return_value = (
                mock_result_with_date_cols
            )
            # Mock withColumnRenamed for surrogate key
            mock_result_df.withColumnRenamed.return_value = mock_result_df
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                result = job.create_core_model(spark_session, mock_args)

            # Assert
            assert (
                mock_read_table.call_count == 2
            )  # Only 2 tables now (removed ebdb_offer)
            mock_surrogate_helper.generate_surrogate_key.assert_called_once()
            assert result == mock_result_with_date_cols

    def test_create_core_model_logs_incremental_mode(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test create_core_model logs INCREMENTAL mode when dates are provided."""
        # Mock the functions within the loaded module
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            # Arrange
            job = CoreOfferSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = "2025-01-01"
            mock_args.load_end_date = "2025-01-31"

            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_result_df.withColumnRenamed.return_value = mock_result_df
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration and logger
            with (
                patch.object(job, "get_offer_config") as mock_config,
                patch.object(job, "logger") as mock_logger,
            ):
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                job.create_core_model(spark_session, mock_args)

                # Assert
                mock_logger.info.assert_any_call(
                    "m=create_core_model, mode=INCREMENTAL, load_start_date=2025-01-01, load_end_date=2025-01-31"
                )

    def test_create_core_model_logs_full_mode_with_none_dates(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test create_core_model logs FULL mode when dates are None."""
        # Mock the functions within the loaded module
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            # Arrange
            job = CoreOfferSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = None
            mock_args.load_end_date = None

            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_result_df.withColumnRenamed.return_value = mock_result_df
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration and logger
            with (
                patch.object(job, "get_offer_config") as mock_config,
                patch.object(job, "logger") as mock_logger,
            ):
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                job.create_core_model(spark_session, mock_args)

                # Assert
                mock_logger.info.assert_any_call(
                    "m=create_core_model, mode=FULL, msg=Running full load without date filtering"
                )

    def test_create_core_model_filters_deleted_records(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test create_core_model filters out records with op_cdc = 'd'."""
        # Arrange
        job = CoreOfferSparkJob()
        mock_args = Mock()
        mock_args.load_start_date = None
        mock_args.load_end_date = None

        # Mock table reads to return our test DataFrames
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]

            # Mock SurrogateKeysHelper to return a DataFrame that preserves the input structure
            def mock_generate_surrogate_key(df, entity_type, id_column):
                # Add sk_core_offer column and return it
                return df.withColumn("sk_core_offer", lit(f"sk_{entity_type}_123"))

            mock_surrogate_helper.generate_surrogate_key.side_effect = (
                mock_generate_surrogate_key
            )

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act - Call the actual method
                result_df = job.create_core_model(spark_session, mock_args)

                # Assert - Check that deleted records are filtered out
                # Original test data has 4 records, but 1 has op_cdc = 'd', so should have 3
                result_count = result_df.count()
                assert result_count == 3, (
                    f"Expected 3 records after filtering, got {result_count}"
                )

                # Verify that the deleted record (offer_4) is not in the result
                result_ids = [
                    row["id_offer"] for row in result_df.select("id_offer").collect()
                ]
                assert 4 not in result_ids, "Deleted record should not be present"
                assert 1 in result_ids, "Non-deleted record should be present"

    def test_create_core_model_joins_user_data_correctly(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test create_core_model correctly joins with user data for tenant and owner."""
        # Arrange
        job = CoreOfferSparkJob()
        mock_args = Mock()
        mock_args.load_start_date = None
        mock_args.load_end_date = None

        # Mock table reads
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]

            # Mock SurrogateKeysHelper to return a DataFrame that preserves the input structure
            def mock_generate_surrogate_key(df, entity_type, id_column):
                return df.withColumn("sk_core_offer", lit(f"sk_{entity_type}_123"))

            mock_surrogate_helper.generate_surrogate_key.side_effect = (
                mock_generate_surrogate_key
            )

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                result_df = job.create_core_model(spark_session, mock_args)

                # Assert - Check that JOIN worked correctly
                result_data = result_df.select(
                    "id_offer",
                    "id_tenant",
                    "id_owner",
                    "id_tenant_external",
                    "id_owner_external",
                ).collect()

                # Find offer_1 in results
                offer_1_data = [row for row in result_data if row["id_offer"] == 1][0]
                assert offer_1_data["id_tenant"] == 101, "Tenant JOIN failed"
                assert offer_1_data["id_owner"] == 102, "Owner JOIN failed"
                assert offer_1_data["id_tenant_external"] == "tenant_uuid_1", (
                    "External tenant ID missing"
                )
                assert offer_1_data["id_owner_external"] == "owner_uuid_1", (
                    "External owner ID missing"
                )

    def test_create_core_model_adds_year_month_day_columns(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test that create_core_model correctly adds year, month, day columns based on ts_created."""
        # Arrange
        job = CoreOfferSparkJob()
        mock_args = Mock()
        mock_args.load_start_date = None
        mock_args.load_end_date = None

        # Mock table reads to return our test DataFrames
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]

            # Mock SurrogateKeysHelper to return a DataFrame that preserves the input structure
            def mock_generate_surrogate_key(df, entity_type, id_column):
                return df.withColumn("sk_core_offer", lit(f"sk_{entity_type}_123"))

            mock_surrogate_helper.generate_surrogate_key.side_effect = (
                mock_generate_surrogate_key
            )

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                result_df = job.create_core_model(spark_session, mock_args)

                # Assert - Check that year, month, day columns are present
                result_columns = result_df.columns
                assert "year" in result_columns, "year column should be present"
                assert "month" in result_columns, "month column should be present"
                assert "day" in result_columns, "day column should be present"

                # Collect data to validate the values
                result_data = result_df.select(
                    "ts_created", "year", "month", "day"
                ).collect()

                # Validate that year, month, day values are correctly derived from ts_created
                for row in result_data:
                    ts_created = row["ts_created"]
                    expected_year = ts_created.year
                    expected_month = ts_created.month
                    expected_day = ts_created.day

                    assert row["year"] == expected_year, (
                        f"Year should be {expected_year}, got {row['year']}"
                    )
                    assert row["month"] == expected_month, (
                        f"Month should be {expected_month}, got {row['month']}"
                    )
                    assert row["day"] == expected_day, (
                        f"Day should be {expected_day}, got {row['day']}"
                    )

    def test_create_core_model_with_date_filtering(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test create_core_model applies date filtering when dates provided."""
        # Arrange
        job = CoreOfferSparkJob()
        mock_args = Mock()
        mock_args.load_start_date = "2025-01-01"
        mock_args.load_end_date = "2025-01-31"

        # Mock table reads
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]

            # Mock SurrogateKeysHelper
            def mock_generate_surrogate_key(df, entity_type, id_column):
                return df.withColumn("sk_core_offer", lit(f"sk_{entity_type}_123"))

            mock_surrogate_helper.generate_surrogate_key.side_effect = (
                mock_generate_surrogate_key
            )

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                result_df = job.create_core_model(spark_session, mock_args)

                # Assert - Check that only records within date range are included
                # offer_4 has ts_updated = 2022-12-25 (before range) and should be excluded
                # Plus it has op_cdc = 'd' so would be filtered anyway
                # offers 1, 2, 3 have ts_updated in 2025-01-01 to 2025-01-03 (within range)
                result_data = result_df.select("id_offer", "ts_updated").collect()

                # Should have 3 records (offers 1, 2, 3) - offer_4 excluded by both date and CDC filter
                assert len(result_data) == 3, (
                    f"Expected 3 records with date filtering, got {len(result_data)}"
                )

                result_ids = [row["id_offer"] for row in result_data]
                assert 1 in result_ids, "offer_1 should be included (within date range)"
                assert 2 in result_ids, "offer_2 should be included (within date range)"
                assert 3 in result_ids, "offer_3 should be included (within date range)"
                assert 4 not in result_ids, (
                    "offer_4 should be excluded (outside date range and deleted)"
                )

    def test_create_core_model_has_all_expected_columns(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test that create_core_model includes all expected columns in the output."""
        # Arrange
        job = CoreOfferSparkJob()
        mock_args = Mock()
        mock_args.load_start_date = None
        mock_args.load_end_date = None

        # Mock table reads
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]

            # Mock SurrogateKeysHelper
            def mock_generate_surrogate_key(df, entity_type, id_column):
                return df.withColumn("sk_core_offer", lit(f"sk_{entity_type}_123"))

            mock_surrogate_helper.generate_surrogate_key.side_effect = (
                mock_generate_surrogate_key
            )

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                result_df = job.create_core_model(spark_session, mock_args)

                # Assert - Check all expected columns are present
                result_columns = set(result_df.columns)
                expected_columns = {
                    "sk_core_offer",
                    "id_offer",
                    "uuid_offer",
                    "id_tenant",
                    "id_tenant_external",
                    "id_owner",
                    "id_owner_external",
                    "id_resident_info",
                    "id_house",
                    "status",
                    "type",
                    "turn",
                    "iteration",
                    "rejection_reason",
                    "original_rent_value",
                    "ts_created",
                    "ts_updated",
                    "ts_expiration",
                    "ts_load",
                    "year",
                    "month",
                    "day",
                }

                missing_columns = expected_columns - result_columns
                extra_columns = result_columns - expected_columns

                assert not missing_columns, (
                    f"Missing expected columns: {missing_columns}"
                )
                assert not extra_columns, f"Unexpected extra columns: {extra_columns}"
                assert len(result_columns) == 22, (
                    f"Expected 22 columns, got {len(result_columns)}"
                )

    def test_create_core_model_uuid_offer_mapping(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test that uuid_offer is correctly mapped from source and preserved through transformations."""
        # Arrange
        job = CoreOfferSparkJob()
        mock_args = Mock()
        mock_args.load_start_date = None
        mock_args.load_end_date = None

        # Mock table reads
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]

            # Mock SurrogateKeysHelper
            def mock_generate_surrogate_key(df, entity_type, id_column):
                return df.withColumn("sk_core_offer", lit(f"sk_{entity_type}_123"))

            mock_surrogate_helper.generate_surrogate_key.side_effect = (
                mock_generate_surrogate_key
            )

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                result_df = job.create_core_model(spark_session, mock_args)

                # Assert - Verify uuid_offer is present and correctly mapped
                result_data = result_df.select("id_offer", "uuid_offer").collect()

                # Check that uuid_offer column exists and has correct values
                assert len(result_data) == 3, (
                    "Should have 3 records (excluding deleted)"
                )

                # Verify uuid_offer values are correctly mapped from source
                expected_mappings = {
                    1: "offer_uuid_1",
                    2: "offer_uuid_2",
                    3: "offer_uuid_3",
                }

                for row in result_data:
                    id_offer = row["id_offer"]
                    uuid_offer = row["uuid_offer"]

                    # Verify uuid_offer is not null
                    assert uuid_offer is not None, (
                        f"uuid_offer should not be null for id_offer={id_offer}"
                    )

                    # Verify uuid_offer has correct value from source
                    assert uuid_offer == expected_mappings[id_offer], (
                        f"uuid_offer mismatch for id_offer={id_offer}: "
                        f"expected {expected_mappings[id_offer]}, got {uuid_offer}"
                    )

                # Verify uuid_offer values are unique
                uuid_values = [row["uuid_offer"] for row in result_data]
                assert len(uuid_values) == len(set(uuid_values)), (
                    "uuid_offer values should be unique"
                )

    def test_create_core_model_uuid_offer_completeness(
        self, spark_session, rental_transact_offer_df, ebdb_user_df
    ):
        """Test that uuid_offer is complete (no null values) in the output."""
        # Arrange
        job = CoreOfferSparkJob()
        mock_args = Mock()
        mock_args.load_start_date = None
        mock_args.load_end_date = None

        # Mock table reads
        with (
            patch.object(spark_session, "table") as mock_read_table,
            patch.object(
                load_core_offer, "SurrogateKeysHelper"
            ) as mock_surrogate_helper,
        ):
            mock_read_table.side_effect = [rental_transact_offer_df, ebdb_user_df]

            # Mock SurrogateKeysHelper
            def mock_generate_surrogate_key(df, entity_type, id_column):
                return df.withColumn("sk_core_offer", lit(f"sk_{entity_type}_123"))

            mock_surrogate_helper.generate_surrogate_key.side_effect = (
                mock_generate_surrogate_key
            )

            # Mock the configuration
            with patch.object(job, "get_offer_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "OFFER",
                    "RENTAL_TRANSACT_OFFER_TABLE": "test_rental_transact_offer_table",
                    "EBDB_USER_TABLE": "test_ebdb_user_table",
                }

                # Act
                result_df = job.create_core_model(spark_session, mock_args)

                # Assert - Check that uuid_offer has no null values
                null_count = result_df.filter(col("uuid_offer").isNull()).count()
                assert null_count == 0, (
                    f"uuid_offer should not have null values, found {null_count} nulls"
                )

                # Verify total count matches expected (3 non-deleted records)
                total_count = result_df.count()
                assert total_count == 3, f"Expected 3 records, got {total_count}"


class TestSparkSessionInitialization:
    """Test cases for Spark session initialization - isolated to this DAG context."""

    def test_initialize_spark_session_returns_spark_session(self):
        """Test initialize_spark_session returns a SparkSession."""
        # Arrange
        job = CoreOfferSparkJob()

        # Act
        result = job.initialize_spark_session()

        # Assert
        assert result is not None


class TestArgumentParsing:
    """Test cases for argument parsing - isolated to this DAG context."""

    @patch(
        "sys.argv",
        [
            "load_core_offer.py",
            "forno",
            "test-bucket",
            "core_offer",
            "core",
            "offer",
            "2025-01-01",
            "2025-01-31",
            "--extra_spark_job_arguments",
            "{}",
        ],
    )
    def test_parse_args_with_all_arguments(self):
        """Test parse_args with all command line arguments provided."""
        # Arrange
        job = CoreOfferSparkJob()

        # Act
        args = job.parse_args()

        # Assert
        assert args.environment == "forno"
        assert args.bucket == "test-bucket"
        assert args.dag_name == "core_offer"
        assert args.schema == "core"
        assert args.table_name == "offer"
        assert args.load_start_date == "2025-01-01"
        assert args.load_end_date == "2025-01-31"
        assert args.extra_spark_job_arguments == "{}"
        assert args.table_privileges is None


class TestJobConstants:
    """Test cases for job constants - isolated to this DAG context."""

    def test_job_name_constant(self):
        """Test JOB_NAME constant is defined correctly."""
        # Assert
        assert JOB_NAME == "core_offer"


# Pytest markers for conditional test execution
pytestmark = [
    pytest.mark.core_model,  # Mark for core model tests
    pytest.mark.spark,  # Mark for Spark tests
    pytest.mark.dag_specific,  # Mark for DAG-specific tests
]
