import unittest
import pytest
from unittest.mock import patch, Mock, MagicMock, call
from argparse import Namespace
import ast
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

# Import the functions we want to test
import sys
import os
# Navigate from tests/primitives_dags/comms_manager_rules/tests/unit/ to dags/primitives/comms_manager_rules/spark_jobs/
spark_jobs_path = os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..', 'dags', 'primitives', 'comms_manager_rules', 'spark_jobs')
sys.path.append(spark_jobs_path)

from load_comms_manager_rules import (
    get_last_version,
    read_communication_rules_json,
    explode_rules,
    explode_and_flatten_actions,
    process_communication_rules,
    write_dataframe_with_s3_loader,
    parse_arguments,
    main,
    JOB_NAME
)


class TestGetLastVersion(unittest.TestCase):
    """Test cases for get_last_version function."""

    @patch('load_comms_manager_rules.col')
    @patch('load_comms_manager_rules.BaseDBUtils')
    @patch('load_comms_manager_rules.spark')
    def test_get_last_version_success(self, mock_spark, mock_base_dbutils, mock_col):
        """Test successful retrieval of latest file."""
        # Mock dbutils and file listing
        mock_dbutils = Mock()
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils

        # Mock file list
        mock_files = [
            Mock(path="s3://path/file1.json", modificationTime=1000),
            Mock(path="s3://path/file2.json", modificationTime=2000),
            Mock(path="s3://path/file3.json", modificationTime=1500)
        ]
        mock_dbutils.fs.ls.return_value = mock_files

        # Mock DataFrame operations
        mock_df = Mock()
        mock_spark.createDataFrame.return_value = mock_df
        mock_df.orderBy.return_value = mock_df
        mock_df.limit.return_value = mock_df
        mock_df.collect.return_value = [Mock(path="s3://path/file2.json", modificationTime=2000)]

        # Mock col function
        mock_col.return_value = Mock()
        mock_col.return_value.desc.return_value = "mocked_col_desc"

        # Test
        result = get_last_version("s3://test-path/")

        # Assertions
        self.assertEqual(result, "s3://path/file2.json")
        mock_dbutils.fs.ls.assert_called_once_with("s3://test-path/")
        mock_spark.createDataFrame.assert_called_once_with(mock_files)

    @patch('load_comms_manager_rules.BaseDBUtils')
    def test_get_last_version_no_files(self, mock_base_dbutils):
        """Test behavior when no files are found."""
        # Mock dbutils with empty file list
        mock_dbutils = Mock()
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils
        mock_dbutils.fs.ls.return_value = []

        # Test
        result = get_last_version("s3://empty-path/")

        # Assertions
        self.assertIsNone(result)

    @patch('load_comms_manager_rules.BaseDBUtils')
    def test_get_last_version_exception(self, mock_base_dbutils):
        """Test exception handling."""
        # Mock dbutils to raise exception
        mock_dbutils = Mock()
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils
        mock_dbutils.fs.ls.side_effect = Exception("S3 access failed")

        # Test
        with self.assertRaises(Exception) as context:
            get_last_version("s3://error-path/")

        self.assertIn("S3 access failed", str(context.exception))


class TestDataProcessingFunctions(unittest.TestCase):
    """Test cases for data processing functions."""

    @patch('load_comms_manager_rules.spark')
    def test_read_communication_rules_json_success(self, mock_spark):
        """Test successful JSON reading."""
        # Mock DataFrame
        mock_df = Mock(spec=DataFrame)
        mock_spark.read.option.return_value.json.return_value = mock_df
        mock_df.count.return_value = 5

        # Test
        result = read_communication_rules_json("s3://test-path/file.json")

        # Assertions
        self.assertEqual(result, mock_df)
        mock_spark.read.option.assert_called_once_with("multiline", "true")

    @patch('load_comms_manager_rules.spark')
    def test_read_communication_rules_json_exception(self, mock_spark):
        """Test exception handling in JSON reading."""
        # Mock exception
        mock_spark.read.option.return_value.json.side_effect = Exception("File not found")

        # Test
        with self.assertRaises(Exception) as context:
            read_communication_rules_json("s3://invalid-path/file.json")

        self.assertIn("File not found", str(context.exception))

    @patch('load_comms_manager_rules.explode')
    @patch('load_comms_manager_rules.to_timestamp')
    @patch('load_comms_manager_rules.col')
    def test_explode_rules(self, mock_col, mock_to_timestamp, mock_explode):
        """Test rules explosion function with proper mocking."""
        # Mock DataFrame
        mock_df = Mock(spec=DataFrame)
        mock_exploded_df = Mock(spec=DataFrame)

        mock_df.select.return_value = mock_exploded_df
        mock_exploded_df.count.return_value = 10

        # Mock Spark functions to return mock objects that can be chained
        mock_col.return_value = Mock()
        mock_to_timestamp.return_value = Mock()
        mock_to_timestamp.return_value.alias.return_value = "generated_at_alias"
        mock_explode.return_value = Mock()
        mock_explode.return_value.alias.return_value = "rule_alias"

        # Test - this calls the REAL function with mocked Spark functions
        result = explode_rules(mock_df)

        # Assertions
        self.assertEqual(result, mock_exploded_df)
        mock_df.select.assert_called_once()
        mock_col.assert_called_with("metadata.generated_at")
        mock_to_timestamp.assert_called_once()
        mock_explode.assert_called_with("rules")

    @patch('load_comms_manager_rules.dayofmonth')
    @patch('load_comms_manager_rules.month')
    @patch('load_comms_manager_rules.year')
    @patch('load_comms_manager_rules.explode')
    @patch('load_comms_manager_rules.col')
    def test_explode_and_flatten_actions(self, mock_col, mock_explode, mock_year, mock_month, mock_dayofmonth):
        """Test action explosion and flattening function with proper mocking."""
        # Mock DataFrame chain
        mock_rules_df = Mock(spec=DataFrame)
        mock_with_actions_df = Mock(spec=DataFrame)
        mock_flat_df = Mock(spec=DataFrame)

        mock_with_year_df = Mock(spec=DataFrame)
        mock_with_month_df = Mock(spec=DataFrame)
        mock_with_day_df = Mock(spec=DataFrame)

        mock_rules_df.select.return_value = mock_with_actions_df
        mock_with_actions_df.select.return_value = mock_flat_df

        # Chain the withColumn calls: flat_df -> year_df -> month_df -> day_df
        mock_flat_df.withColumn.return_value = mock_with_year_df
        mock_with_year_df.withColumn.return_value = mock_with_month_df
        mock_with_month_df.withColumn.return_value = mock_with_day_df
        mock_with_day_df.count.return_value = 25

        # Mock Spark functions to return mock objects that can be chained
        mock_col_instance = Mock()
        mock_col_instance.alias.return_value = "mocked_col_with_alias"
        mock_col.return_value = mock_col_instance

        mock_explode_instance = Mock()
        mock_explode_instance.alias.return_value = "mocked_explode_with_alias"
        mock_explode.return_value = mock_explode_instance

        # Mock date functions
        mock_year.return_value = "mocked_year"
        mock_month.return_value = "mocked_month"
        mock_dayofmonth.return_value = "mocked_day"

        # Test - this calls the REAL function with mocked Spark functions
        result = explode_and_flatten_actions(mock_rules_df)

        # Assertions
        self.assertEqual(result, mock_with_day_df)  # Final result should be the last DataFrame in the chain
        self.assertEqual(mock_rules_df.select.call_count, 1)
        self.assertEqual(mock_with_actions_df.select.call_count, 1)

        # Verify each DataFrame's withColumn was called once
        mock_flat_df.withColumn.assert_called_once()
        mock_with_year_df.withColumn.assert_called_once()
        mock_with_month_df.withColumn.assert_called_once()

        # Verify Spark functions were called correctly
        mock_col.assert_any_call("rule.scope.profile")
        mock_col.assert_any_call("action.profile")
        mock_explode.assert_called_with("rule.actions")

        # Verify date functions were called
        mock_year.assert_called_once_with(mock_col.return_value)
        mock_month.assert_called_once_with(mock_col.return_value)
        mock_dayofmonth.assert_called_once_with(mock_col.return_value)

    @patch('load_comms_manager_rules.explode_and_flatten_actions')
    @patch('load_comms_manager_rules.explode_rules')
    @patch('load_comms_manager_rules.read_communication_rules_json')
    def test_process_communication_rules_success(self, mock_read_json, mock_explode_rules, mock_explode_actions):
        """Test complete processing pipeline."""
        # Mock the pipeline
        mock_raw_df = Mock(spec=DataFrame)
        mock_rules_df = Mock(spec=DataFrame)
        mock_flat_df = Mock(spec=DataFrame)

        mock_read_json.return_value = mock_raw_df
        mock_explode_rules.return_value = mock_rules_df
        mock_explode_actions.return_value = mock_flat_df

        # Test
        result = process_communication_rules("s3://test-path/file.json")

        # Assertions
        self.assertEqual(result, mock_flat_df)
        mock_read_json.assert_called_once_with("s3://test-path/file.json")
        mock_explode_rules.assert_called_once_with(mock_raw_df)
        mock_explode_actions.assert_called_once_with(mock_rules_df)

    @patch('load_comms_manager_rules.read_communication_rules_json')
    def test_process_communication_rules_exception(self, mock_read_json):
        """Test exception handling in processing pipeline."""
        # Mock exception
        mock_read_json.side_effect = Exception("Processing failed")

        # Test
        with self.assertRaises(Exception) as context:
            process_communication_rules("s3://error-path/file.json")

        self.assertIn("Processing failed", str(context.exception))


class TestS3LoaderFunction(unittest.TestCase):
    """Test cases for S3Loader writing function."""

    @patch('load_comms_manager_rules.S3Loader')
    @patch('load_comms_manager_rules.SparkTableStorageFormat')
    def test_write_dataframe_with_s3_loader_success(self, mock_storage_format, mock_s3_loader_class):
        """Test successful DataFrame writing with S3Loader."""
        # Mock DataFrame
        mock_df = Mock(spec=DataFrame)
        mock_df.count.return_value = 100

        # Mock S3Loader
        mock_s3_loader = Mock()
        mock_s3_loader_class.return_value = mock_s3_loader
        mock_storage_format.DEFAULT_RAW = "JSON"

        # Test with partitions
        write_dataframe_with_s3_loader(
            mock_df,
            "s3://bucket/path/",
            "['year', 'month', 'day']"
        )

        # Assertions
        mock_s3_loader_class.assert_called_once()
        mock_s3_loader.load_df.assert_called_once_with(
            df=mock_df,
            s3_path="s3://bucket/path/",
            format_options="JSON",
            partitions=['year', 'month', 'day'],
            optimize_dataframe=False,
        )

    @patch('load_comms_manager_rules.S3Loader')
    @patch('load_comms_manager_rules.SparkTableStorageFormat')
    def test_write_dataframe_with_s3_loader_no_partitions(self, mock_storage_format, mock_s3_loader_class):
        """Test DataFrame writing without partitions."""
        # Mock DataFrame
        mock_df = Mock(spec=DataFrame)
        mock_df.count.return_value = 50

        # Mock S3Loader
        mock_s3_loader = Mock()
        mock_s3_loader_class.return_value = mock_s3_loader
        mock_storage_format.DEFAULT_RAW = "JSON"

        # Test without partitions
        write_dataframe_with_s3_loader(mock_df, "s3://bucket/path/", None)

        # Assertions
        mock_s3_loader.load_df.assert_called_once_with(
            df=mock_df,
            s3_path="s3://bucket/path/",
            format_options="JSON",
            partitions=None,
            optimize_dataframe=False,
        )

    @patch('load_comms_manager_rules.S3Loader')
    def test_write_dataframe_with_s3_loader_invalid_partitions(self, mock_s3_loader_class):
        """Test handling of invalid partition format."""
        # Mock DataFrame
        mock_df = Mock(spec=DataFrame)
        mock_df.count.return_value = 75

        # Mock S3Loader
        mock_s3_loader = Mock()
        mock_s3_loader_class.return_value = mock_s3_loader

        # Test with invalid partition format
        write_dataframe_with_s3_loader(mock_df, "s3://bucket/path/", "invalid_format")

        # Should call with partitions=None due to parsing error
        mock_s3_loader.load_df.assert_called_once()
        call_args = mock_s3_loader.load_df.call_args
        self.assertIsNone(call_args[1]['partitions'])

    @patch('load_comms_manager_rules.S3Loader')
    def test_write_dataframe_with_s3_loader_exception(self, mock_s3_loader_class):
        """Test exception handling in S3Loader writing."""
        # Mock DataFrame
        mock_df = Mock(spec=DataFrame)

        # Mock S3Loader to raise exception
        mock_s3_loader = Mock()
        mock_s3_loader_class.return_value = mock_s3_loader
        mock_s3_loader.load_df.side_effect = Exception("S3 write failed")

        # Test
        with self.assertRaises(Exception) as context:
            write_dataframe_with_s3_loader(mock_df, "s3://bucket/path/", None)

        self.assertIn("S3 write failed", str(context.exception))


class TestArgumentParsing(unittest.TestCase):
    """Test cases for argument parsing function."""

    @patch('sys.argv', ['script.py', 'prod', 'bucket', 'dag', 'schema', 'table', "['year']", '2024-01-01', 's3://path/'])
    def test_parse_arguments_success(self):
        """Test successful argument parsing."""
        args = parse_arguments()

        self.assertEqual(args.environment, 'prod')
        self.assertEqual(args.datalake_bucket, 'bucket')
        self.assertEqual(args.dag_name, 'dag')
        self.assertEqual(args.schema, 'schema')
        self.assertEqual(args.table_name, 'table')
        self.assertEqual(args.partitions, "['year']")
        self.assertEqual(args.execution_date, '2024-01-01')
        self.assertEqual(args.comms_manager_rules_path, 's3://path/')

    @patch('sys.argv', ['script.py', 'prod', 'bucket', 'dag', 'schema', 'table', '2024-01-01', 's3://path/'])
    def test_parse_arguments_optional_partitions(self):
        """Test argument parsing with optional partitions."""
        args = parse_arguments()

        self.assertEqual(args.environment, 'prod')
        self.assertEqual(args.datalake_bucket, 'bucket')
        self.assertEqual(args.dag_name, 'dag')
        self.assertEqual(args.schema, 'schema')
        self.assertEqual(args.table_name, 'table')
        self.assertIsNone(args.partitions)  # Should be None when not provided
        self.assertEqual(args.execution_date, '2024-01-01')
        self.assertEqual(args.comms_manager_rules_path, 's3://path/')


class TestMainFunction(unittest.TestCase):
    """Test cases for main function."""

    # Using fixtures from conftest.py instead of setUp

    @patch('load_comms_manager_rules.write_dataframe_with_s3_loader')
    @patch('load_comms_manager_rules.process_communication_rules')
    @patch('load_comms_manager_rules.get_last_version')
    @patch('load_comms_manager_rules.parse_arguments')
    @patch('load_comms_manager_rules.logging.basicConfig')
    def test_main_success(self, mock_logging_config, mock_parse_args, mock_get_version,
                         mock_process_rules, mock_write_s3):
        """Test successful main function execution."""
        # Create mock arguments
        from argparse import Namespace
        mock_args = Namespace(
            environment='prod',
            datalake_bucket='test-bucket',
            dag_name='comms_manager_rules',
            schema='comms_manager',
            table_name='comms_manager_rules',
            partitions="['year', 'month', 'day']",
            execution_date='2024-01-01',
            comms_manager_rules_path='s3://comms-manager-{environment}/notification-rules/versions/'
        )
        mock_parse_args.return_value = mock_args

        # Mock pipeline
        mock_get_version.return_value = "s3://path/latest-file.json"
        mock_processed_dataframe = Mock(spec=DataFrame)
        mock_process_rules.return_value = mock_processed_dataframe

        # Test
        main()

        # Assertions
        mock_parse_args.assert_called_once()
        mock_logging_config.assert_called_once()
        mock_get_version.assert_called_once_with('s3://comms-manager-prod/notification-rules/versions/')
        mock_process_rules.assert_called_once_with("s3://path/latest-file.json")
        mock_write_s3.assert_called_once_with(
            mock_processed_dataframe,
            "s3://test-bucket/raw/comms_manager/comms_manager_rules",
            "['year', 'month', 'day']"
        )
        mock_processed_dataframe.printSchema.assert_called_once()

    @patch('load_comms_manager_rules.get_last_version')
    @patch('load_comms_manager_rules.parse_arguments')
    @patch('load_comms_manager_rules.logging.basicConfig')
    def test_main_no_files_found(self, mock_logging_config, mock_parse_args, mock_get_version):
        """Test main function when no files are found."""
        # Create mock arguments
        from argparse import Namespace
        mock_args = Namespace(
            environment='prod',
            datalake_bucket='test-bucket',
            dag_name='comms_manager_rules',
            schema='comms_manager',
            table_name='comms_manager_rules',
            partitions="['year', 'month', 'day']",
            execution_date='2024-01-01',
            comms_manager_rules_path='s3://comms-manager-{environment}/notification-rules/versions/'
        )
        mock_parse_args.return_value = mock_args

        # Mock no files found
        mock_get_version.return_value = None

        # Test
        result = main()

        # Assertions
        self.assertIsNone(result)  # Should return None when no files
        mock_get_version.assert_called_once_with('s3://comms-manager-prod/notification-rules/versions/')

    @patch('load_comms_manager_rules.get_last_version')
    @patch('load_comms_manager_rules.parse_arguments')
    @patch('load_comms_manager_rules.logging.basicConfig')
    def test_main_exception_handling(self, mock_logging_config, mock_parse_args, mock_get_version):
        """Test main function exception handling."""
        # Create mock arguments
        from argparse import Namespace
        mock_args = Namespace(
            environment='prod',
            datalake_bucket='test-bucket',
            dag_name='comms_manager_rules',
            schema='comms_manager',
            table_name='comms_manager_rules',
            partitions="['year', 'month', 'day']",
            execution_date='2024-01-01',
            comms_manager_rules_path='s3://comms-manager-{environment}/notification-rules/versions/'
        )
        mock_parse_args.return_value = mock_args

        # Mock exception
        mock_get_version.side_effect = Exception("Test exception")

        # Test
        with self.assertRaises(Exception) as context:
            main()

        self.assertIn("Test exception", str(context.exception))


class TestIntegration(unittest.TestCase):
    """Integration test cases."""

    @patch('load_comms_manager_rules.write_dataframe_with_s3_loader')
    @patch('load_comms_manager_rules.explode_and_flatten_actions')
    @patch('load_comms_manager_rules.explode_rules')
    @patch('load_comms_manager_rules.read_communication_rules_json')
    @patch('load_comms_manager_rules.get_last_version')
    def test_full_pipeline_integration(self, mock_get_version, mock_read_json, mock_explode_rules,
                                     mock_explode_actions, mock_write_s3):
        """Test full pipeline integration."""
        # Mock the entire pipeline
        mock_get_version.return_value = "s3://path/file.json"

        mock_raw_df = Mock(spec=DataFrame)
        mock_rules_df = Mock(spec=DataFrame)
        mock_flat_df = Mock(spec=DataFrame)

        mock_read_json.return_value = mock_raw_df
        mock_explode_rules.return_value = mock_rules_df
        mock_explode_actions.return_value = mock_flat_df

        # Test
        result = process_communication_rules("s3://test-path/file.json")

        # Assertions
        self.assertEqual(result, mock_flat_df)
        mock_read_json.assert_called_once_with("s3://test-path/file.json")
        mock_explode_rules.assert_called_once_with(mock_raw_df)
        mock_explode_actions.assert_called_once_with(mock_rules_df)


if __name__ == '__main__':
    unittest.main()
