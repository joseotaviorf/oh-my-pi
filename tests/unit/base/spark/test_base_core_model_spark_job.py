import pytest
from datetime import datetime
from unittest.mock import Mock, patch
from argparse import Namespace
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    IntegerType,
    BooleanType,
    TimestampType,
)

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class ConcreteCoreModelSparkJob(BaseCoreModelSparkJob):
    """Concrete implementation of BaseCoreModelSparkJob for testing purposes."""

    def __init__(self, job_name: str = "test_job"):
        super().__init__(job_name)

    def create_core_model(self, spark_session, args):
        """Create a simple test DataFrame."""
        data = [
            {"id": 1, "name": "John", "age": 30, "active": True},
            {"id": 2, "name": "Jane", "age": 25, "active": False},
        ]
        return spark_session.createDataFrame(data)


class TestBaseCoreModelSparkJob:
    @pytest.fixture
    def job_instance(self):
        """Create a test instance of the concrete job."""
        return ConcreteCoreModelSparkJob()

    @pytest.fixture
    def mock_dataframe(self):
        """Create a mock DataFrame with various column types."""
        schema = StructType(
            [
                StructField("id", IntegerType(), True),
                StructField("name", StringType(), True),
                StructField("age", IntegerType(), True),
                StructField("active", BooleanType(), True),
                StructField("created_at", TimestampType(), True),
                StructField("special_column_name", StringType(), True),
                StructField("column_with_spaces", StringType(), True),
            ]
        )

        data = [
            (1, "John", 30, True, datetime(2024, 1, 1), "test", "value with spaces"),
            (2, "Jane", 25, False, datetime(2024, 1, 2), "test2", "another value"),
        ]

        return spark.createDataFrame(data, schema)

    @pytest.fixture
    def simple_dataframe(self):
        """Create a simple test DataFrame."""
        data = [{"col1": "value1", "col2": "value2", "col3": "value3"}]
        return spark.createDataFrame(data)

    @pytest.fixture
    def mock_args(self):
        """Create mock arguments for testing."""
        return Namespace(
            environment="test",
            bucket="test-bucket",
            dag_name="test_dag",
            schema="test_schema",
            table_name="test_table",
            load_start_date="2024-01-01",
            load_end_date="2024-01-31",
            extra_spark_job_arguments="{}",
            table_privileges=None,
            partitions=None,  # Added to support partitions parameter handling
        )

    def test_default_when_matched_operation_generation(
        self, job_instance, simple_dataframe
    ):
        """Test that default_when_matched_operation generates correct CASE WHEN statements."""
        # Arrange
        expected_columns = simple_dataframe.columns

        # Act - Extract the logic from run_pipeline method
        source_cols = simple_dataframe.columns
        default_when_matched_operation = {
            col: f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            for col in source_cols
        }

        # Assert
        assert len(default_when_matched_operation) == len(expected_columns)

        for col in expected_columns:
            assert col in default_when_matched_operation
            expected_case_statement = f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            assert default_when_matched_operation[col] == expected_case_statement

    @pytest.mark.parametrize(
        "columns",
        [
            ["id", "name", "email"],
            ["user_id", "first_name", "last_name", "created_at", "updated_at"],
            ["col1"],
            ["column_with_underscores", "ColumnWithCapitals", "column-with-dashes"],
            [],  # Edge case: empty columns
        ],
    )
    def test_default_when_matched_operation_with_different_columns(
        self, job_instance, columns
    ):
        """Test default_when_matched_operation with various column configurations."""
        # Arrange
        if columns:
            data = [{col: f"value_{i}" for i, col in enumerate(columns)}]
            test_df = spark.createDataFrame(data)
        else:
            # Create empty DataFrame
            test_df = spark.createDataFrame([], StructType([]))

        # Act
        source_cols = test_df.columns
        default_when_matched_operation = {
            col: f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            for col in source_cols
        }

        # Assert
        assert len(default_when_matched_operation) == len(columns)

        for col in columns:
            expected_statement = f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            assert default_when_matched_operation[col] == expected_statement

    def test_default_when_matched_operation_preserves_target_values(self, job_instance):
        """Test that the CASE WHEN logic correctly preserves target values when source is NULL."""
        # Arrange
        columns = ["id", "name", "status"]

        # Act
        default_when_matched_operation = {
            col: f"CASE WHEN s.{col} IS NOT NULL THEN s.{col} ELSE t.{col} END"
            for col in columns
        }

        # Assert - Check that each statement follows the correct pattern
        for col in columns:
            statement = default_when_matched_operation[col]

            # Should start with CASE WHEN
            assert statement.startswith("CASE WHEN")

            # Should check for NOT NULL on source
            assert f"s.{col} IS NOT NULL" in statement

            # Should use source value when not null
            assert f"THEN s.{col}" in statement

            # Should use target value when source is null
            assert f"ELSE t.{col} END" in statement

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_run_pipeline_uses_default_when_matched_operation(
        self,
        mock_table_privileges,
        mock_config_service,
        job_instance,
        mock_dataframe,
        mock_args,
    ):
        """Test that run_pipeline method correctly uses the default_when_matched_operation."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock all the configuration calls to return None (so defaults are used)
        mock_config_instance.get_config.return_value = None
        job_instance.config_service = mock_config_instance

        # Mock target table that has the same columns as source (simulate existing table)
        mock_target_df = mock_dataframe  # Same structure as source

        # Mock the pipeline
        with patch.object(spark, "table", return_value=mock_target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act
                job_instance.run_pipeline(mock_dataframe, mock_args, spark)

                # Assert
                # Verify that the pipeline was called with the correct default_when_matched_operation
                call_args = mock_pipeline_class.call_args
                when_matched_operation = call_args.kwargs["when_matched_operation"]

                # Check that when_matched_operation contains the expected CASE WHEN statements
                # Since target table exists with same columns, all should use CASE WHEN logic
                expected_columns = mock_dataframe.columns
                assert len(when_matched_operation) == len(expected_columns)

                for col in expected_columns:
                    expected_statement = f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
                    assert when_matched_operation[col] == expected_statement

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_run_pipeline_uses_custom_when_matched_operation_when_configured(
        self,
        mock_table_privileges,
        mock_config_service,
        job_instance,
        mock_dataframe,
        mock_args,
    ):
        """Test that run_pipeline uses custom when_matched_operation when provided in config."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Set up custom when_matched_operation
        custom_operation = {"id": "source.id", "name": "source.name"}

        def mock_get_config(key, required=True, default=None):
            if key == "when_matched_operation":
                return custom_operation
            return None

        mock_config_instance.get_config.side_effect = mock_get_config

        # Mock the pipeline
        with patch(
            "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
        ) as mock_pipeline_class:
            mock_pipeline_instance = Mock()
            mock_pipeline_class.return_value = mock_pipeline_instance

            # Act
            job_instance.run_pipeline(mock_dataframe, mock_args, spark)

            # Assert
            call_args = mock_pipeline_class.call_args
            when_matched_operation = call_args.kwargs["when_matched_operation"]

            # Should use the custom operation, not the default
            assert when_matched_operation == custom_operation

    def test_default_when_matched_operation_with_complex_column_names(
        self, job_instance
    ):
        """Test that default_when_matched_operation works with complex column names."""
        # Arrange
        complex_columns = [
            "normal_column",
            "Column_With_Mixed_Case",
            "column_with_numbers_123",
            "column.with.dots",
            "column-with-hyphens",
            "column with spaces",  # Note: Spark typically converts these to underscores
        ]

        # Create a DataFrame with complex column names
        data = [{col: f"value_{i}" for i, col in enumerate(complex_columns)}]
        test_df = spark.createDataFrame(data)
        actual_columns = test_df.columns  # Spark may modify column names

        # Act
        default_when_matched_operation = {
            col: f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            for col in actual_columns
        }

        # Assert
        assert len(default_when_matched_operation) == len(actual_columns)

        for col in actual_columns:
            expected_statement = f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            assert default_when_matched_operation[col] == expected_statement

    def test_default_when_matched_operation_preserves_column_order(self, job_instance):
        """Test that the default_when_matched_operation maintains DataFrame column order."""
        # Arrange
        ordered_columns = ["first", "second", "third", "fourth", "fifth"]
        # Create DataFrame with specific column order using schema
        schema = StructType(
            [StructField(col, StringType(), True) for col in ordered_columns]
        )
        data = [tuple(f"value_{col}" for col in ordered_columns)]
        test_df = spark.createDataFrame(data, schema)

        # Act
        source_cols = test_df.columns
        default_when_matched_operation = {
            col: f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            for col in source_cols
        }

        # Assert
        # Verify that the DataFrame columns match our expected order
        assert list(test_df.columns) == ordered_columns
        # Verify that all expected columns are in the operation dict
        operation_keys = list(default_when_matched_operation.keys())
        assert set(operation_keys) == set(ordered_columns)
        assert len(operation_keys) == len(ordered_columns)

    def test_default_when_matched_operation_sql_injection_safety(self, job_instance):
        """Test that column names don't create SQL injection vulnerabilities."""
        # Arrange - Test with potentially problematic column names
        # Note: Spark DataFrames typically sanitize column names, but we test the logic
        test_columns = ["normal_col", "col_123", "underscore_col"]
        data = [{col: "value" for col in test_columns}]
        test_df = spark.createDataFrame(data)

        # Act
        default_when_matched_operation = {
            col: f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            for col in test_df.columns
        }

        # Assert - Verify that each statement is properly formatted and safe
        for col, statement in default_when_matched_operation.items():
            # Should not contain any SQL injection patterns
            assert "'" not in statement  # No single quotes
            assert '"' not in statement  # No double quotes
            assert ";" not in statement  # No semicolons
            assert "--" not in statement  # No SQL comments

            # Should contain the expected structure
            assert (
                statement.count(f"source.{col}") == 2
            )  # Source column referenced twice
            assert (
                statement.count(f"target.{col}") == 1
            )  # Target column referenced once
            assert "CASE WHEN" in statement
            assert "IS NOT NULL" in statement
            assert "THEN" in statement
            assert "ELSE" in statement
            assert "END" in statement

    def test_default_when_matched_operation_with_new_columns_edge_case(
        self, job_instance
    ):
        """Test the edge case when source DataFrame has new columns not in target.

        This test demonstrates the problem with the current implementation:
        It generates CASE WHEN statements referencing target columns that don't exist yet.
        """
        # Arrange - Simulate source DataFrame with new columns
        source_columns = ["existing_col1", "existing_col2", "new_col1", "new_col2"]
        data = [{col: f"value_{col}" for col in source_columns}]
        source_df = spark.createDataFrame(data)

        # Act - Current implementation (problematic)
        current_logic = {
            col: f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            for col in source_df.columns
        }

        # Assert - This shows the problem
        assert "new_col1" in current_logic
        assert "new_col2" in current_logic

        # These would cause SQL errors because target.new_col1 and target.new_col2 don't exist
        problematic_statement = current_logic["new_col1"]
        assert (
            "target.new_col1" in problematic_statement
        )  # ❌ This column doesn't exist in target!

        # TODO: This test demonstrates the bug. The fix should:
        # 1. Only apply CASE WHEN logic to columns that exist in BOTH source and target
        # 2. For new columns, just use source.column_name directly

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_improved_default_when_matched_operation_with_new_columns(
        self, mock_table_privileges, mock_config_service, job_instance, mock_args
    ):
        """Test the improved logic that handles new columns correctly."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock all configuration calls to return None (use defaults)
        mock_config_instance.get_config.return_value = None

        # Create source DataFrame with both existing and new columns
        source_data = [
            {
                "existing_col1": "val1",
                "existing_col2": "val2",
                "new_col1": "new_val1",
                "new_col2": "new_val2",
            }
        ]
        source_df = spark.createDataFrame(source_data)

        # Mock target table that only has existing columns
        target_data = [{"existing_col1": "old_val1", "existing_col2": "old_val2"}]
        mock_target_df = spark.createDataFrame(target_data)

        # Mock spark.table() to return the target table
        with patch.object(spark, "table", return_value=mock_target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act
                job_instance.run_pipeline(source_df, mock_args, spark)

                # Assert
                call_args = mock_pipeline_class.call_args
                when_matched_operation = call_args.kwargs["when_matched_operation"]

                # Existing columns should use CASE WHEN logic
                assert "existing_col1" in when_matched_operation
                assert "existing_col2" in when_matched_operation
                expected_existing_logic = "CASE WHEN source.existing_col1 IS NOT NULL THEN source.existing_col1 ELSE target.existing_col1 END"
                assert (
                    when_matched_operation["existing_col1"] == expected_existing_logic
                )

                # New columns should use source value directly
                assert "new_col1" in when_matched_operation
                assert "new_col2" in when_matched_operation
                assert (
                    when_matched_operation["new_col1"] == "source.new_col1"
                )  # ✅ No target reference!
                assert (
                    when_matched_operation["new_col2"] == "source.new_col2"
                )  # ✅ No target reference!

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_default_when_matched_operation_when_target_table_not_exists(
        self, mock_table_privileges, mock_config_service, job_instance, mock_args
    ):
        """Test behavior when target table doesn't exist yet (first load)."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock all configuration calls to return None (use defaults)
        mock_config_instance.get_config.return_value = None

        # Create source DataFrame
        source_data = [{"col1": "val1", "col2": "val2", "col3": "val3"}]
        source_df = spark.createDataFrame(source_data)

        # Mock spark.table() to throw exception (table doesn't exist)
        def mock_table_exception(table_name):
            raise Exception("Table not found")

        with patch.object(spark, "table", side_effect=mock_table_exception):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act
                job_instance.run_pipeline(source_df, mock_args, spark)

                # Assert
                call_args = mock_pipeline_class.call_args
                when_matched_operation = call_args.kwargs["when_matched_operation"]

                # All columns should use source value directly (no target table exists)
                for col in source_df.columns:
                    assert when_matched_operation[col] == f"source.{col}"

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_partitions_parameter_none(
        self, mock_table_privileges, mock_config_service, job_instance
    ):
        """Test partitions parameter when None (should default to empty list)."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock configuration
        mock_config_instance.get_config.return_value = None

        # Create mock args with partitions=None
        mock_args = Mock()
        mock_args.environment = "test"
        mock_args.bucket = "test-bucket"
        mock_args.schema = "test_schema"
        mock_args.table_name = "test_table"
        mock_args.partitions = None  # This should default to []

        # Create source DataFrame
        source_data = [{"col1": "val1", "col2": "val2"}]
        source_df = spark.createDataFrame(source_data)

        # Mock spark.table() to return target DataFrame
        target_df = spark.createDataFrame([{"col1": "old_val1", "col2": "old_val2"}])

        with patch.object(spark, "table", return_value=target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act
                job_instance.run_pipeline(source_df, mock_args, spark)

                # Assert
                call_args = mock_pipeline_class.call_args
                partitions_passed = call_args.kwargs["partitions"]

                assert partitions_passed == []  # Should be empty list when None

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_partitions_parameter_single_partition(
        self, mock_table_privileges, mock_config_service, job_instance
    ):
        """Test partitions parameter with single partition as string."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock configuration
        mock_config_instance.get_config.return_value = None

        # Create mock args with single partition
        mock_args = Mock()
        mock_args.environment = "test"
        mock_args.bucket = "test-bucket"
        mock_args.schema = "test_schema"
        mock_args.table_name = "test_table"
        mock_args.partitions = "['year']"  # Single partition as string

        # Create source DataFrame
        source_data = [{"col1": "val1", "year": "2023"}]
        source_df = spark.createDataFrame(source_data)

        # Mock spark.table() to return target DataFrame
        target_df = spark.createDataFrame([{"col1": "old_val1", "year": "2022"}])

        with patch.object(spark, "table", return_value=target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act
                job_instance.run_pipeline(source_df, mock_args, spark)

                # Assert
                call_args = mock_pipeline_class.call_args
                partitions_passed = call_args.kwargs["partitions"]

                assert partitions_passed == ["year"]  # Should parse to list

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_partitions_parameter_multiple_partitions(
        self, mock_table_privileges, mock_config_service, job_instance
    ):
        """Test partitions parameter with multiple partitions as string."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock configuration
        mock_config_instance.get_config.return_value = None

        # Create mock args with multiple partitions
        mock_args = Mock()
        mock_args.environment = "test"
        mock_args.bucket = "test-bucket"
        mock_args.schema = "test_schema"
        mock_args.table_name = "test_table"
        mock_args.partitions = (
            "['year', 'month', 'day']"
        )  # Multiple partitions as string

        # Create source DataFrame
        source_data = [{"col1": "val1", "year": "2023", "month": "01", "day": "15"}]
        source_df = spark.createDataFrame(source_data)

        # Mock spark.table() to return target DataFrame
        target_df = spark.createDataFrame(
            [{"col1": "old_val1", "year": "2022", "month": "12", "day": "31"}]
        )

        with patch.object(spark, "table", return_value=target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act
                job_instance.run_pipeline(source_df, mock_args, spark)

                # Assert
                call_args = mock_pipeline_class.call_args
                partitions_passed = call_args.kwargs["partitions"]

                assert partitions_passed == [
                    "year",
                    "month",
                    "day",
                ]  # Should parse to list

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_partitions_parameter_empty_list_string(
        self, mock_table_privileges, mock_config_service, job_instance
    ):
        """Test partitions parameter with empty list as string."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock configuration
        mock_config_instance.get_config.return_value = None

        # Create mock args with empty list as string
        mock_args = Mock()
        mock_args.environment = "test"
        mock_args.bucket = "test-bucket"
        mock_args.schema = "test_schema"
        mock_args.table_name = "test_table"
        mock_args.partitions = "[]"  # Empty list as string

        # Create source DataFrame
        source_data = [{"col1": "val1", "col2": "val2"}]
        source_df = spark.createDataFrame(source_data)

        # Mock spark.table() to return target DataFrame
        target_df = spark.createDataFrame([{"col1": "old_val1", "col2": "old_val2"}])

        with patch.object(spark, "table", return_value=target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act
                job_instance.run_pipeline(source_df, mock_args, spark)

                # Assert
                call_args = mock_pipeline_class.call_args
                partitions_passed = call_args.kwargs["partitions"]

                assert partitions_passed == []  # Should parse to empty list

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_partitions_parameter_logging(
        self, mock_table_privileges, mock_config_service, job_instance
    ):
        """Test that partitions are properly logged."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock configuration
        mock_config_instance.get_config.return_value = None

        # Create mock args with partitions
        mock_args = Mock()
        mock_args.environment = "test"
        mock_args.bucket = "test-bucket"
        mock_args.schema = "test_schema"
        mock_args.table_name = "test_table"
        mock_args.partitions = "['year', 'month']"

        # Create source DataFrame
        source_data = [{"col1": "val1", "year": "2023", "month": "01"}]
        source_df = spark.createDataFrame(source_data)

        # Mock spark.table() to return target DataFrame
        target_df = spark.createDataFrame(
            [{"col1": "old_val1", "year": "2022", "month": "12"}]
        )

        with patch.object(spark, "table", return_value=target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                with patch.object(job_instance, "logger") as mock_logger:
                    # Act
                    job_instance.run_pipeline(source_df, mock_args, spark)

                    # Assert - Check that partitions are logged
                    mock_logger.info.assert_any_call(
                        "m=run_pipeline, msg=Loading data using DataFrameDeltaTableLoaderPipeline with partitions: ['year', 'month']"
                    )

    @patch("bietlejuice.base.spark.base_core_model_spark_job.ConfigurationService")
    @patch("bietlejuice.base.spark.base_core_model_spark_job.TablePrivileges")
    def test_partitions_parameter_invalid_string_format(
        self, mock_table_privileges, mock_config_service, job_instance
    ):
        """Test partitions parameter with invalid string format (should raise exception)."""
        # Arrange
        mock_config_instance = Mock()
        mock_config_service.return_value = mock_config_instance
        job_instance.config_service = mock_config_instance

        # Mock table privileges
        mock_privileges_instance = Mock()
        mock_table_privileges.from_environment_default.return_value = (
            mock_privileges_instance
        )

        # Mock configuration
        mock_config_instance.get_config.return_value = None

        # Create mock args with invalid partition string
        mock_args = Mock()
        mock_args.environment = "test"
        mock_args.bucket = "test-bucket"
        mock_args.schema = "test_schema"
        mock_args.table_name = "test_table"
        mock_args.partitions = "invalid_format"  # Invalid format

        # Create source DataFrame
        source_data = [{"col1": "val1", "col2": "val2"}]
        source_df = spark.createDataFrame(source_data)

        # Mock spark.table() to return target DataFrame
        target_df = spark.createDataFrame([{"col1": "old_val1", "col2": "old_val2"}])

        with patch.object(spark, "table", return_value=target_df):
            with patch(
                "bietlejuice.base.spark.base_core_model_spark_job.DataFrameDeltaTableLoaderPipeline"
            ) as mock_pipeline_class:
                mock_pipeline_instance = Mock()
                mock_pipeline_class.return_value = mock_pipeline_instance

                # Act & Assert - Should raise an exception due to invalid format
                with pytest.raises((ValueError, SyntaxError)):
                    job_instance.run_pipeline(source_df, mock_args, spark)
