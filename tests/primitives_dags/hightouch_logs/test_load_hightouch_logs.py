import pytest
import unittest
from unittest.mock import Mock, patch, MagicMock
from argparse import Namespace
import logging

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
        self.mock_df = Mock()
        self.mock_df.count.return_value = 100

        # Sample arguments
        self.sample_args = Namespace(
            environment='prod',
            datalake_bucket='test-bucket',
            schema='hightouch_logs',
            source='hightouch_logs',
            table_name='sync_changelog_databricks',
            input_path='s3://test-bucket/path/{environment}/data',
            format='delta'
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
    def test_read_input_from_s3_parquet(self, mock_spark):
        """Test reading input from S3 with parquet format."""
        # Arrange
        mock_spark.read.format.return_value.load.return_value = self.mock_df
        input_path = 's3://test-bucket/data'
        format_type = 'parquet'

        # Act
        result = read_input(input_path, format_type)

        # Assert
        mock_spark.read.format.assert_called_once_with('parquet')
        mock_spark.read.format.return_value.load.assert_called_once_with(input_path)
        self.assertEqual(result, self.mock_df)

    @patch('load_hightouch_logs.spark')
    def test_read_input_from_catalog_table(self, mock_spark):
        """Test reading input from catalog table."""
        # Arrange
        mock_spark.table.return_value = self.mock_df
        table_name = 'hightouch_audit.sync_changelog_view'
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
        table_name = 'hightouch_audit.sync_changelog_view'
        format_type = 'TABLE'

        # Act
        result = read_input(table_name, format_type)

        # Assert
        mock_spark.table.assert_called_once_with(table_name)
        self.assertEqual(result, self.mock_df)

    @patch('load_hightouch_logs.FullTableLoaderPipeline')
    @patch('load_hightouch_logs.SparkMetastoreService')
    @patch('load_hightouch_logs.DatalakeMetastoreService')
    @patch('load_hightouch_logs.SparkTableStorageFormat')
    @patch('load_hightouch_logs.spark_client')
    def test_load_table_into_datalake_success(self, mock_spark_client, mock_storage_format,
                                            mock_datalake_service, mock_metastore_service,
                                            mock_pipeline):
        """Test successful loading of table into datalake."""
        # Arrange
        mock_db_info = {
            "db_raw_databricks": "datalake_hightouch_logs_raw",
            "db_raw_path": "s3://bucket/raw/path"
        }
        mock_datalake_service.get_db_info.return_value = mock_db_info
        mock_storage_format.DEFAULT_RAW = "json_format"

        mock_metastore_instance = Mock()
        mock_metastore_service.return_value = mock_metastore_instance

        mock_pipeline_instance = Mock()
        mock_pipeline.return_value = mock_pipeline_instance

        # Act
        load_table_into_datalake(
            df=self.mock_df,
            table_name='test_table',
            environment='prod',
            source='hightouch_logs',
            datalake_bucket='test-bucket'
        )

        # Assert
        mock_datalake_service.get_db_info.assert_called_once_with('prod', 'hightouch_logs', 'test-bucket')
        mock_metastore_instance.create_database.assert_called_once_with("datalake_hightouch_logs_raw")
        mock_pipeline_instance.load_and_register.assert_called_once()

    @patch('load_hightouch_logs.FullTableLoaderPipeline')
    @patch('load_hightouch_logs.SparkMetastoreService')
    @patch('load_hightouch_logs.DatalakeMetastoreService')
    def test_load_table_into_datalake_exception(self, mock_datalake_service,
                                              mock_metastore_service, mock_pipeline):
        """Test exception handling in load_table_into_datalake."""
        # Arrange
        mock_datalake_service.get_db_info.side_effect = Exception("Database error")

        # Act & Assert
        with self.assertRaises(Exception) as context:
            load_table_into_datalake(
                df=self.mock_df,
                table_name='test_table',
                environment='prod',
                source='hightouch_logs',
                datalake_bucket='test-bucket'
            )

        self.assertIn("Database error", str(context.exception))

    @patch('sys.argv', ['load_hightouch_logs.py', 'prod', 'test-bucket', 'hightouch_logs',
                        'hightouch_logs', 'sync_changelog', 's3://test/path', 'delta'])
    def test_parse_arguments_success(self):
        """Test successful argument parsing."""
        # Act
        args = parse_arguments()

        # Assert
        self.assertEqual(args.environment, 'prod')
        self.assertEqual(args.datalake_bucket, 'test-bucket')
        self.assertEqual(args.schema, 'hightouch_logs')
        self.assertEqual(args.source, 'hightouch_logs')
        self.assertEqual(args.table_name, 'sync_changelog')
        self.assertEqual(args.input_path, 's3://test/path')
        self.assertEqual(args.format, 'delta')

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
            datalake_bucket='test-bucket',
            schema='hightouch_logs',
            source='hightouch_logs',
            table_name='sync_changelog',
            input_path='s3://test-bucket/path/{environment}/data',
            format='delta'
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
                "datalake_bucket": "test-bucket",
                "schema": "hightouch_logs",
                "source": "hightouch_logs",
                "table_name": "sync_changelog",
                "input_path": "s3://test-bucket/path/prod/data",  # {environment} should be replaced
                "format": "delta"
            }
            mock_read_input.assert_called_once_with(**expected_params)

    def test_environment_placeholder_replacement(self):
        """Test that environment placeholder is correctly replaced."""
        # Arrange
        template_path = "s3://bucket/{environment}/data"
        environment = "prod"

        # Act
        resolved_path = template_path.format(environment=environment)

        # Assert
        self.assertEqual(resolved_path, "s3://bucket/prod/data")

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

    @patch('load_hightouch_logs.load_table_into_datalake')
    @patch('load_hightouch_logs.read_input')
    @patch('sys.argv', ['load_hightouch_logs.py', 'prod', 'test-bucket', 'hightouch_logs',
                        'hightouch_logs', 'sync_changelog', 's3://test/{environment}/data', 'delta'])
    def test_end_to_end_s3_flow(self, mock_read_input, mock_load_table):
        """Test end-to-end flow with S3 input."""
        # Arrange
        mock_df = Mock()
        mock_df.count.return_value = 50
        mock_read_input.return_value = mock_df

        # Act
        main()

        # Assert
        expected_params = {
            "environment": "prod",
            "datalake_bucket": "test-bucket",
            "schema": "hightouch_logs",
            "source": "hightouch_logs",
            "table_name": "sync_changelog",
            "input_path": "s3://test/prod/data",  # Environment replaced
            "format": "delta"
        }
        mock_read_input.assert_called_once_with(**expected_params)
        mock_load_table.assert_called_once_with(mock_df, **expected_params)

    @patch('load_hightouch_logs.load_table_into_datalake')
    @patch('load_hightouch_logs.read_input')
    @patch('sys.argv', ['load_hightouch_logs.py', 'prod', 'test-bucket', 'hightouch_logs',
                        'hightouch_logs', 'sync_changelog', 'catalog.schema.table', 'table'])
    def test_end_to_end_catalog_flow(self, mock_read_input, mock_load_table):
        """Test end-to-end flow with catalog table input."""
        # Arrange
        mock_df = Mock()
        mock_df.count.return_value = 75
        mock_read_input.return_value = mock_df

        # Act
        main()

        # Assert
        expected_params = {
            "environment": "prod",
            "datalake_bucket": "test-bucket",
            "schema": "hightouch_logs",
            "source": "hightouch_logs",
            "table_name": "sync_changelog",
            "input_path": "catalog.schema.table",
            "format": "table"
        }
        mock_read_input.assert_called_once_with(**expected_params)
        mock_load_table.assert_called_once_with(mock_df, **expected_params)


if __name__ == '__main__':
    unittest.main()
