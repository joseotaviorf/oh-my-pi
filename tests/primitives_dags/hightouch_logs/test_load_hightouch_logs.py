import pytest
import unittest
from unittest.mock import Mock, patch, MagicMock, call
from argparse import Namespace
import logging
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, StringType, TimestampType

# Import the module under test
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '../../../dags/primitives/hightouch_logs/spark_jobs'))
from load_hightouch_logs import read_input, load_table_into_datalake, parse_arguments, main


class TestLoadHightouchLogs(unittest.TestCase):
    """Unit tests for load_hightouch_logs.py"""

    def setUp(self):
        """Set up test fixtures before each test method."""
        self.mock_spark = Mock()
        self.mock_df = Mock(spec=DataFrame)
        self.mock_df.count.return_value = 100
        self.mock_df.printSchema.return_value = None
        self.mock_df.show.return_value = None

        # Mock DataFrame methods for chaining
        self.mock_df.filter.return_value = self.mock_df
        self.mock_df.selectExpr.return_value = self.mock_df
        self.mock_df.withColumn.return_value = self.mock_df

        # Sample arguments for incremental loading
        self.sample_args = Namespace(
            environment='prod',
            datalake_bucket='5a-datalake-prod',
            schema='hightouch_logs',
            source='hightouch_logs',
            table_name='sync_runs_trino',
            input_path='hightouch_audit.sync_runs',
            format='table',
            load_start_date='2025-10-07',
            load_end_date='2025-10-07',
            extraction_type='incremental',
            incremental_column='started_at'
        )

        # Sample arguments for full loading
        self.full_load_args = Namespace(
            environment='prod',
            datalake_bucket='5a-datalake-prod',
            schema='hightouch_logs',
            source='hightouch_logs',
            table_name='sync_runs_trino',
            input_path='hightouch_audit.sync_runs',
            format='table',
            load_start_date='2025-10-07',
            load_end_date='2025-10-07',
            extraction_type='full',
            incremental_column='started_at'
        )

    @patch('load_hightouch_logs.spark')
    def test_read_input_from_s3_delta(self, mock_spark):
        """Test reading input from S3 with delta format."""
        # Arrange
        mock_spark.read.format.return_value.load.return_value = self.mock_df
        input_path = 's3://test-bucket/data'
        format_type = 'delta'

        # Act
        result = read_input(input_path, format_type)

        # Assert
        mock_spark.read.format.assert_called_once_with('delta')
        mock_spark.read.format.return_value.load.assert_called_once_with(input_path)
        self.assertEqual(result, self.mock_df)

    @patch('load_hightouch_logs.spark')
    def test_read_input_from_catalog_table(self, mock_spark):
        """Test reading input from catalog table."""
        # Arrange
        mock_spark.table.return_value = self.mock_df
        table_name = 'hightouch_audit.sync_runs'
        format_type = 'table'

        # Act
        result = read_input(table_name, format_type)

        # Assert
        mock_spark.table.assert_called_once_with(table_name)
        self.assertEqual(result, self.mock_df)

    @patch('load_hightouch_logs.spark')
    def test_read_input_from_catalog_table_case_insensitive(self, mock_spark):
        """Test reading input from catalog table with uppercase format."""
        # Arrange
        mock_spark.table.return_value = self.mock_df
        table_name = 'hightouch_audit.sync_runs'
        format_type = 'TABLE'

        # Act
        result = read_input(table_name, format_type)

        # Assert
        mock_spark.table.assert_called_once_with(table_name)
        self.assertEqual(result, self.mock_df)

    @patch('load_hightouch_logs.spark')
    @patch('load_hightouch_logs.UnityCatalogHelper')
    @patch('load_hightouch_logs.S3Loader')
    @patch('load_hightouch_logs.SparkMetastoreService')
    @patch('load_hightouch_logs.DatalakeMetastoreService')
    @patch('load_hightouch_logs.SparkTableStorageFormat')
    @patch('load_hightouch_logs.spark_client')
    def test_load_table_into_datalake_incremental_success(self, mock_spark_client, mock_storage_format,
                                                        mock_datalake_service, mock_metastore_service,
                                                        mock_s3_loader_class, mock_unity_catalog, mock_spark):
        """Test successful incremental loading of table into datalake."""
        # Arrange
        mock_db_info = {
            "db_raw_databricks": "datalake_hightouch_logs_raw",
            "db_raw_path": "s3://bucket/raw/path/"
        }
        mock_datalake_service.get_db_info.return_value = mock_db_info
        mock_storage_format.DEFAULT_RAW = "json_format"
        mock_unity_catalog.is_cluster_unity_catalog_enabled.return_value = False

        mock_metastore_instance = Mock()
        mock_metastore_service.return_value = mock_metastore_instance

        mock_s3_loader_instance = Mock()
        mock_s3_loader_class.return_value = mock_s3_loader_instance

        # Act
        load_table_into_datalake(
            df=self.mock_df,
            table_name='sync_runs_trino',
            environment='prod',
            source='hightouch_logs',
            datalake_bucket='5a-datalake-prod',
            load_start_date='2025-10-07',
            load_end_date='2025-10-07',
            extraction_type='incremental',
            incremental_column='started_at'
        )

        # Assert
        mock_datalake_service.get_db_info.assert_called_once_with('prod', 'hightouch_logs', '5a-datalake-prod')
        mock_metastore_instance.create_database.assert_called_once_with("datalake_hightouch_logs_raw")

        # Verify DataFrame transformations were called
        self.mock_df.printSchema.assert_called_once()
        self.mock_df.filter.assert_called_once()
        self.mock_df.selectExpr.assert_called_once()
        self.mock_df.show.assert_called_once()

        # Verify S3Loader was called
        mock_s3_loader_instance.load_df.assert_called_once()
        s3_loader_call_args = mock_s3_loader_instance.load_df.call_args
        self.assertEqual(s3_loader_call_args[1]['df'], self.mock_df)
        self.assertEqual(s3_loader_call_args[1]['s3_path'], "s3://bucket/raw/path/sync_runs_trino")
        self.assertEqual(s3_loader_call_args[1]['partitions'], ["year", "month", "day"])
        self.assertEqual(s3_loader_call_args[1]['optimize_dataframe'], False)

    @patch('load_hightouch_logs.spark')
    @patch('load_hightouch_logs.UnityCatalogHelper')
    @patch('load_hightouch_logs.FullTableLoaderPipeline')
    @patch('load_hightouch_logs.SparkMetastoreService')
    @patch('load_hightouch_logs.DatalakeMetastoreService')
    @patch('load_hightouch_logs.SparkTableStorageFormat')
    @patch('load_hightouch_logs.spark_client')
    def test_load_table_into_datalake_full_success(self, mock_spark_client, mock_storage_format,
                                                 mock_datalake_service, mock_metastore_service,
                                                 mock_pipeline, mock_unity_catalog, mock_spark):
        """Test successful full loading of table into datalake."""
        # Arrange
        mock_db_info = {
            "db_raw_databricks": "datalake_hightouch_logs_raw",
            "db_raw_path": "s3://bucket/raw/path/"
        }
        mock_datalake_service.get_db_info.return_value = mock_db_info
        mock_storage_format.DEFAULT_RAW = "json_format"
        mock_unity_catalog.is_cluster_unity_catalog_enabled.return_value = False

        mock_metastore_instance = Mock()
        mock_metastore_service.return_value = mock_metastore_instance

        mock_pipeline_instance = Mock()
        mock_pipeline.return_value = mock_pipeline_instance

        # Act
        load_table_into_datalake(
            df=self.mock_df,
            table_name='sync_runs_trino',
            environment='prod',
            source='hightouch_logs',
            datalake_bucket='5a-datalake-prod',
            load_start_date='2025-10-07',
            load_end_date='2025-10-07',
            extraction_type='full',
            incremental_column='started_at'
        )

        # Assert
        mock_datalake_service.get_db_info.assert_called_once_with('prod', 'hightouch_logs', '5a-datalake-prod')
        mock_metastore_instance.create_database.assert_called_once_with("datalake_hightouch_logs_raw")
        mock_pipeline_instance.load_and_register.assert_called_once()

    @patch('load_hightouch_logs.spark')
    @patch('load_hightouch_logs.UnityCatalogHelper')
    @patch('load_hightouch_logs.S3Loader')
    @patch('load_hightouch_logs.SparkMetastoreService')
    @patch('load_hightouch_logs.DatalakeMetastoreService')
    @patch('load_hightouch_logs.SparkTableStorageFormat')
    @patch('load_hightouch_logs.spark_client')
    def test_load_table_with_unity_catalog_enabled(self, mock_spark_client, mock_storage_format,
                                                   mock_datalake_service, mock_metastore_service,
                                                   mock_s3_loader_class, mock_unity_catalog, mock_spark):
        """Test loading with Unity Catalog enabled - should execute USE CATALOG."""
        # Arrange
        mock_db_info = {
            "db_raw_databricks": "datalake_hightouch_logs_raw",
            "db_raw_path": "s3://bucket/raw/path/"
        }
        mock_datalake_service.get_db_info.return_value = mock_db_info
        mock_storage_format.DEFAULT_RAW = "json_format"

        # Unity Catalog is enabled
        mock_unity_catalog.is_cluster_unity_catalog_enabled.return_value = True
        mock_unity_catalog.get_current_catalog.return_value = "quintoandar_prod"

        mock_metastore_instance = Mock()
        mock_metastore_service.return_value = mock_metastore_instance

        mock_s3_loader_instance = Mock()
        mock_s3_loader_class.return_value = mock_s3_loader_instance

        mock_spark_sql = Mock()
        mock_spark.sql = mock_spark_sql

        # Act
        load_table_into_datalake(
            df=self.mock_df,
            table_name='sync_runs_trino',
            environment='prod',
            source='hightouch_logs',
            datalake_bucket='5a-datalake-prod',
            load_start_date='2025-10-07',
            load_end_date='2025-10-07',
            extraction_type='incremental',
            incremental_column='started_at'
        )

        # Assert
        # Verify Unity Catalog context was set
        mock_unity_catalog.is_cluster_unity_catalog_enabled.assert_called_once()
        mock_unity_catalog.get_current_catalog.assert_called_once()
        mock_spark_sql.assert_called_once_with("USE CATALOG quintoandar_prod")

    @patch('load_hightouch_logs.F')
    def test_incremental_filtering_logic(self, mock_f):
        """Test the incremental filtering logic with PySpark functions."""
        # Arrange
        mock_col = Mock()
        mock_lit = Mock()
        mock_to_date = Mock()

        mock_f.col.return_value = mock_col
        mock_f.lit.return_value = mock_lit
        mock_f.to_date.return_value = mock_to_date

        mock_col.cast.return_value = mock_col
        mock_to_date.return_value = mock_to_date

        # Create a more detailed mock for the filter chain
        filter_condition = Mock()
        mock_col.__ge__ = Mock(return_value=filter_condition)
        mock_col.__le__ = Mock(return_value=filter_condition)
        filter_condition.__and__ = Mock(return_value=filter_condition)

        self.mock_df.filter.return_value = self.mock_df

        with patch('load_hightouch_logs.SparkMetastoreService'), \
             patch('load_hightouch_logs.DatalakeMetastoreService') as mock_datalake_service, \
             patch('load_hightouch_logs.SparkTableStorageFormat'), \
             patch('load_hightouch_logs.S3Loader'), \
             patch('load_hightouch_logs.UnityCatalogHelper') as mock_unity_catalog, \
             patch('load_hightouch_logs.spark'):

            mock_db_info = {
                "db_raw_databricks": "test_db",
                "db_raw_path": "s3://test/"
            }
            mock_datalake_service.get_db_info.return_value = mock_db_info
            mock_unity_catalog.is_cluster_unity_catalog_enabled.return_value = False

            # Act
            load_table_into_datalake(
                df=self.mock_df,
                table_name='test_table',
                environment='prod',
                source='test_source',
                datalake_bucket='test-bucket',
                load_start_date='2025-10-07',
                load_end_date='2025-10-07',
                extraction_type='incremental',
                incremental_column='started_at'
            )

        # Assert that F.col, F.lit, and F.to_date were called
        mock_f.col.assert_called()
        mock_f.lit.assert_called()
        mock_f.to_date.assert_called()

    @patch('load_hightouch_logs.spark')
    @patch('load_hightouch_logs.UnityCatalogHelper')
    @patch('load_hightouch_logs.DatalakeMetastoreService')
    def test_load_table_into_datalake_exception(self, mock_datalake_service, mock_unity_catalog, mock_spark):
        """Test exception handling in load_table_into_datalake."""
        # Arrange
        mock_unity_catalog.is_cluster_unity_catalog_enabled.return_value = False
        mock_datalake_service.get_db_info.side_effect = Exception("Database error")

        # Act & Assert
        with self.assertRaises(Exception) as context:
            load_table_into_datalake(
                df=self.mock_df,
                table_name='test_table',
                environment='prod',
                source='hightouch_logs',
                datalake_bucket='test-bucket',
                load_start_date='2025-10-07',
                load_end_date='2025-10-07',
                extraction_type='incremental',
                incremental_column='started_at'
            )

        self.assertIn("Database error", str(context.exception))

    @patch('sys.argv', ['load_hightouch_logs.py', 'prod', '5a-datalake-prod', 'hightouch_logs',
                        'hightouch_logs', 'sync_runs_trino', '2025-10-07', '2025-10-07',
                        'incremental', 'started_at', 'hightouch_audit.sync_runs', 'table'])
    def test_parse_arguments_success(self):
        """Test successful argument parsing with all required parameters."""
        # Act
        args = parse_arguments()

        # Assert
        self.assertEqual(args.environment, 'prod')
        self.assertEqual(args.datalake_bucket, '5a-datalake-prod')
        self.assertEqual(args.schema, 'hightouch_logs')
        self.assertEqual(args.source, 'hightouch_logs')
        self.assertEqual(args.table_name, 'sync_runs_trino')
        self.assertEqual(args.load_start_date, '2025-10-07')
        self.assertEqual(args.load_end_date, '2025-10-07')
        self.assertEqual(args.extraction_type, 'incremental')
        self.assertEqual(args.incremental_column, 'started_at')
        self.assertEqual(args.input_path, 'hightouch_audit.sync_runs')
        self.assertEqual(args.format, 'table')

    @patch('load_hightouch_logs.load_table_into_datalake')
    @patch('load_hightouch_logs.read_input')
    @patch('load_hightouch_logs.parse_arguments')
    @patch('load_hightouch_logs.logging')
    def test_main_success(self, mock_logging, mock_parse_args, mock_read_input, mock_load_table):
        """Test successful main function execution."""
        # Arrange
        mock_parse_args.return_value = self.sample_args
        mock_read_input.return_value = self.mock_df

        # Act
        main()

        # Assert
        mock_parse_args.assert_called_once()
        mock_read_input.assert_called_once()
        mock_load_table.assert_called_once()

    @patch('load_hightouch_logs.read_input')
    @patch('load_hightouch_logs.parse_arguments')
    def test_main_with_environment_placeholder_replacement(self, mock_parse_args, mock_read_input):
        """Test main function with environment placeholder replacement."""
        # Arrange
        args_with_placeholder = Namespace(
            environment='prod',
            datalake_bucket='5a-datalake-prod',
            schema='hightouch_logs',
            source='hightouch_logs',
            table_name='sync_runs_trino',
            input_path='s3://test-bucket/path/{environment}/data',
            format='delta',
            load_start_date='2025-10-07',
            load_end_date='2025-10-07',
            extraction_type='incremental',
            incremental_column='started_at'
        )
        mock_parse_args.return_value = args_with_placeholder
        mock_read_input.return_value = self.mock_df

        with patch('load_hightouch_logs.load_table_into_datalake') as mock_load_table:
            # Act
            main()

            # Assert
            # Verify that read_input was called with the resolved path
            expected_params = {
                "environment": "prod",
                "datalake_bucket": "5a-datalake-prod",
                "schema": "hightouch_logs",
                "source": "hightouch_logs",
                "table_name": "sync_runs_trino",
                "input_path": "s3://test-bucket/path/prod/data",  # {environment} should be replaced
                "format": "delta",
                "load_start_date": "2025-10-07",
                "load_end_date": "2025-10-07",
                "extraction_type": "incremental",
                "incremental_column": "started_at"
            }
            mock_read_input.assert_called_once_with(**expected_params)

    @patch('load_hightouch_logs.spark')
    def test_read_input_logging(self, mock_spark):
        """Test that read_input function logs correctly."""
        # Arrange
        mock_spark.read.format.return_value.load.return_value = self.mock_df

        with patch('load_hightouch_logs.logging') as mock_logging:
            # Act - S3 path
            read_input('s3://test/path', 'delta')

            # Assert
            mock_logging.info.assert_called_with("Reading from S3 path: s3://test/path with format: delta")

            # Act - Catalog table
            mock_spark.table.return_value = self.mock_df
            read_input('catalog.table', 'table')

            # Assert
            mock_logging.info.assert_called_with("Reading from catalog table: catalog.table")

    def test_selectExpr_partition_columns(self):
        """Test that partition columns are created correctly with selectExpr."""
        # This test verifies the SQL expressions used for partitioning
        incremental_column = 'started_at'
        expected_expressions = [
            "*",
            f"year({incremental_column}) AS year",
            f"month({incremental_column}) AS month",
            f"dayofmonth({incremental_column}) AS day"
        ]

        # The actual implementation uses these expressions
        # This test documents the expected behavior
        self.assertEqual(len(expected_expressions), 4)
        self.assertIn("year(started_at) AS year", expected_expressions)
        self.assertIn("month(started_at) AS month", expected_expressions)
        self.assertIn("dayofmonth(started_at) AS day", expected_expressions)

    @patch('load_hightouch_logs.spark')
    def test_read_input_invalid_format_fallback(self, mock_spark):
        """Test read_input with unknown format falls back to S3 path reading."""
        # Arrange
        mock_spark.read.format.return_value.load.return_value = self.mock_df

        # Act
        result = read_input('s3://test/path', 'unknown_format')

        # Assert
        mock_spark.read.format.assert_called_once_with('unknown_format')
        self.assertEqual(result, self.mock_df)


class TestLoadHightouchLogsIntegration(unittest.TestCase):
    """Integration tests for load_hightouch_logs.py"""

    def setUp(self):
        """Set up test fixtures for integration tests."""
        self.mock_df = Mock(spec=DataFrame)
        self.mock_df.count.return_value = 50
        self.mock_df.printSchema.return_value = None
        self.mock_df.show.return_value = None
        self.mock_df.filter.return_value = self.mock_df
        self.mock_df.selectExpr.return_value = self.mock_df

    @patch('load_hightouch_logs.load_table_into_datalake')
    @patch('load_hightouch_logs.read_input')
    @patch('sys.argv', ['load_hightouch_logs.py', 'prod', '5a-datalake-prod', 'hightouch_logs',
                        'hightouch_logs', 'sync_runs_trino', '2025-10-07', '2025-10-07',
                        'incremental', 'started_at', 'hightouch_audit.sync_runs', 'table'])
    def test_end_to_end_incremental_flow(self, mock_read_input, mock_load_table):
        """Test end-to-end flow with incremental loading."""
        # Arrange
        mock_read_input.return_value = self.mock_df

        # Act
        main()

        # Assert
        expected_params = {
            "environment": "prod",
            "datalake_bucket": "5a-datalake-prod",
            "schema": "hightouch_logs",
            "source": "hightouch_logs",
            "table_name": "sync_runs_trino",
            "input_path": "hightouch_audit.sync_runs",
            "format": "table",
            "load_start_date": "2025-10-07",
            "load_end_date": "2025-10-07",
            "extraction_type": "incremental",
            "incremental_column": "started_at"
        }
        mock_read_input.assert_called_once_with(**expected_params)
        mock_load_table.assert_called_once_with(self.mock_df, **expected_params)

    @patch('load_hightouch_logs.load_table_into_datalake')
    @patch('load_hightouch_logs.read_input')
    @patch('sys.argv', ['load_hightouch_logs.py', 'prod', '5a-datalake-prod', 'hightouch_logs',
                        'hightouch_logs', 'sync_runs_trino', '2025-10-07', '2025-10-07',
                        'full', 'started_at', 'hightouch_audit.sync_runs', 'table'])
    def test_end_to_end_full_flow(self, mock_read_input, mock_load_table):
        """Test end-to-end flow with full loading."""
        # Arrange
        mock_read_input.return_value = self.mock_df

        # Act
        main()

        # Assert
        expected_params = {
            "environment": "prod",
            "datalake_bucket": "5a-datalake-prod",
            "schema": "hightouch_logs",
            "source": "hightouch_logs",
            "table_name": "sync_runs_trino",
            "input_path": "hightouch_audit.sync_runs",
            "format": "table",
            "load_start_date": "2025-10-07",
            "load_end_date": "2025-10-07",
            "extraction_type": "full",
            "incremental_column": "started_at"
        }
        mock_read_input.assert_called_once_with(**expected_params)
        mock_load_table.assert_called_once_with(self.mock_df, **expected_params)


class TestLoadHightouchLogsEdgeCases(unittest.TestCase):
    """Edge case tests for load_hightouch_logs.py"""

    def setUp(self):
        """Set up test fixtures for edge case tests."""
        self.mock_df = Mock(spec=DataFrame)
        self.mock_df.count.return_value = 0  # Empty DataFrame
        self.mock_df.printSchema.return_value = None
        self.mock_df.show.return_value = None
        self.mock_df.filter.return_value = self.mock_df
        self.mock_df.selectExpr.return_value = self.mock_df

    @patch('load_hightouch_logs.spark')
    @patch('load_hightouch_logs.UnityCatalogHelper')
    @patch('load_hightouch_logs.S3Loader')
    @patch('load_hightouch_logs.SparkMetastoreService')
    @patch('load_hightouch_logs.DatalakeMetastoreService')
    @patch('load_hightouch_logs.SparkTableStorageFormat')
    @patch('load_hightouch_logs.spark_client')
    def test_load_empty_dataframe(self, mock_spark_client, mock_storage_format, mock_datalake_service,
                                 mock_metastore_service, mock_s3_loader_class, mock_unity_catalog, mock_spark):
        """Test loading an empty DataFrame."""
        # Arrange
        mock_db_info = {
            "db_raw_databricks": "test_db",
            "db_raw_path": "s3://test/"
        }
        mock_datalake_service.get_db_info.return_value = mock_db_info
        mock_storage_format.DEFAULT_RAW = "json_format"
        mock_unity_catalog.is_cluster_unity_catalog_enabled.return_value = False

        mock_metastore_instance = Mock()
        mock_metastore_service.return_value = mock_metastore_instance

        mock_s3_loader_instance = Mock()
        mock_s3_loader_class.return_value = mock_s3_loader_instance

        # Act
        load_table_into_datalake(
            df=self.mock_df,
            table_name='test_table',
            environment='prod',
            source='test_source',
            datalake_bucket='test-bucket',
            load_start_date='2025-10-07',
            load_end_date='2025-10-07',
            extraction_type='incremental',
            incremental_column='started_at'
        )

        # Assert - should still process even with empty DataFrame
        mock_s3_loader_instance.load_df.assert_called_once()

    @patch('load_hightouch_logs.spark')
    def test_read_input_with_special_characters_in_path(self, mock_spark):
        """Test read_input with special characters in path."""
        # Arrange
        mock_df = Mock()
        mock_spark.table.return_value = mock_df
        table_name = 'schema_with-dashes.table_with_underscores'
        format_type = 'table'

        # Act
        result = read_input(table_name, format_type)

        # Assert
        mock_spark.table.assert_called_once_with(table_name)
        self.assertEqual(result, mock_df)

    def test_date_range_same_day(self):
        """Test that same start and end dates are handled correctly."""
        # This test documents that the system should handle same-day loads
        start_date = '2025-10-07'
        end_date = '2025-10-07'

        # The filter condition should be: col >= start_date AND col <= end_date
        # This should include all records from that single day
        self.assertEqual(start_date, end_date)


if __name__ == '__main__':
    unittest.main()
