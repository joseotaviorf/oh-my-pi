"""
Shared test fixtures and configurations for Communication Manager Rules tests.

This module provides common fixtures, mock objects, and test utilities
that can be used across all test modules in the communication manager rules package.
"""

import pytest
from unittest.mock import Mock, MagicMock
from argparse import Namespace
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.types import (
    StructType, StructField, StringType, IntegerType,
    TimestampType, BooleanType, ArrayType, MapType
)


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (SparkSession.builder
            .appName("CommManagerRulesTests")
            .master("local[1]")
            .config("spark.sql.shuffle.partitions", "1")
            .getOrCreate())

    yield spark

    spark.stop()


@pytest.fixture
def mock_dataframe():
    """Create a mock DataFrame for testing."""
    mock_df = Mock(spec=DataFrame)
    mock_df.count.return_value = 100
    mock_df.columns = ["rule_id", "status", "action_id"]
    mock_df.printSchema.return_value = None
    return mock_df


@pytest.fixture
def mock_processed_dataframe():
    """Create a mock processed DataFrame with expected columns."""
    mock_df = Mock(spec=DataFrame)
    mock_df.count.return_value = 250
    mock_df.columns = [
        "rule_id", "status", "business_context", "category", "company",
        "context", "cost_center", "journey_step", "line", "profile", "team",
        "action.action_id", "action.notification_type", "action.profile",
        "action.reason", "action.deep_link",
        "action.templates.subject_template", "action.templates.body_template",
        "action.templates.body_template_path", "action.templates.subject_content",
        "action.templates.body_content", "ts_export_generated_at"
    ]
    mock_df.printSchema.return_value = None
    return mock_df


@pytest.fixture
def mock_args():
    """Create mock command-line arguments."""
    return Namespace(
        environment='prod',
        datalake_bucket='test-bucket',
        dag_name='comms_manager_rules',
        schema='comms_manager',
        table_name='comms_manager_rules',
        partitions="['year', 'month', 'day']",
        execution_date='2024-01-01',
        comms_manager_rules_path='s3://comms-manager-{environment}/notification-rules/versions/'
    )


@pytest.fixture
def mock_args_no_partitions():
    """Create mock command-line arguments without partitions."""
    return Namespace(
        environment='prod',
        datalake_bucket='test-bucket',
        dag_name='comms_manager_rules',
        schema='comms_manager',
        table_name='comms_manager_rules',
        partitions=None,
        execution_date='2024-01-01',
        comms_manager_rules_path='s3://comms-manager-{environment}/notification-rules/versions/'
    )


@pytest.fixture
def sample_file_list():
    """Create a sample file list for S3 operations."""
    return [
        Mock(path="s3://path/file1.json", modificationTime=1000),
        Mock(path="s3://path/file2.json", modificationTime=2000),
        Mock(path="s3://path/file3.json", modificationTime=1500)
    ]


@pytest.fixture
def sample_rules_json():
    """Create sample communication manager rules JSON structure."""
    return {
        "rules": [
            {
                "rule_id": "rule_123",
                "status": "active",
                "scope": {
                    "business_context": "rental",
                    "category": "notification",
                    "company": "quintoandar",
                    "context": "tenant",
                    "cost_center": "operations",
                    "journey_step": "onboarding",
                    "line": "for_rent",
                    "profile": "tenant",
                    "team": "growth"
                },
                "actions": [
                    {
                        "action_id": "action_456",
                        "notification_type": "email",
                        "profile": "tenant",
                        "reason": "welcome",
                        "deep_link": "https://app.com/welcome",
                        "templates": {
                            "subject_template": "Welcome {{name}}",
                            "body_template": "Hello {{name}}, welcome!",
                            "body_template_path": "/templates/welcome.html",
                            "subject_content": "Welcome John",
                            "body_content": "Hello John, welcome!"
                        }
                    },
                    {
                        "action_id": "action_789",
                        "notification_type": "push",
                        "profile": "tenant",
                        "reason": "reminder",
                        "deep_link": "https://app.com/reminder",
                        "templates": {
                            "subject_template": "Reminder {{name}}",
                            "body_template": "Don't forget {{name}}!",
                            "body_template_path": "/templates/reminder.html",
                            "subject_content": "Reminder John",
                            "body_content": "Don't forget John!"
                        }
                    }
                ]
            },
            {
                "rule_id": "rule_456",
                "status": "inactive",
                "scope": {
                    "business_context": "sales",
                    "category": "marketing",
                    "company": "quintoandar",
                    "context": "owner",
                    "cost_center": "marketing",
                    "journey_step": "conversion",
                    "line": "for_sale",
                    "profile": "owner",
                    "team": "sales"
                },
                "actions": [
                    {
                        "action_id": "action_999",
                        "notification_type": "sms",
                        "profile": "owner",
                        "reason": "follow_up",
                        "deep_link": "https://app.com/follow_up",
                        "templates": {
                            "subject_template": "Follow up {{name}}",
                            "body_template": "Thank you {{name}}!",
                            "body_template_path": "/templates/follow_up.html",
                            "subject_content": "Follow up Jane",
                            "body_content": "Thank you Jane!"
                        }
                    }
                ]
            }
        ]
    }


@pytest.fixture
def expected_schema_columns():
    """Define the expected output schema columns."""
    return [
        # Rule-level fields
        "rule_id",
        "status",
        "business_context",
        "category",
        "company",
        "context",
        "cost_center",
        "journey_step",
        "line",
        "profile",
        "team",
        # Action-level fields
        "action.action_id",
        "action.notification_type",
        "action.profile",
        "action.reason",
        "action.deep_link",
        # Template fields
        "action.templates.subject_template",
        "action.templates.body_template",
        "action.templates.body_template_path",
        "action.templates.subject_content",
        "action.templates.body_content",
        # Processing metadata
        "ts_export_generated_at"
    ]


@pytest.fixture
def mandatory_columns():
    """Define mandatory columns that must always be present."""
    return [
        "rule_id",
        "status",
        "action.action_id",
        "action.notification_type",
        "ts_export_generated_at"
    ]


@pytest.fixture
def mock_spark_dataframe_chain():
    """Create a chain of mock DataFrames for testing transformations."""
    # Raw DataFrame (from JSON read)
    mock_raw_df = Mock(spec=DataFrame)
    mock_raw_df.count.return_value = 2  # 2 rules in sample data

    # Rules DataFrame (after exploding rules)
    mock_rules_df = Mock(spec=DataFrame)
    mock_rules_df.count.return_value = 2  # 2 rules
    mock_rules_df.select.return_value = Mock(spec=DataFrame)

    # Actions DataFrame (intermediate step)
    mock_actions_df = Mock(spec=DataFrame)
    mock_actions_df.count.return_value = 3  # 3 total actions across rules
    mock_actions_df.select.return_value = Mock(spec=DataFrame)

    # Final flattened DataFrame
    mock_flat_df = Mock(spec=DataFrame)
    mock_flat_df.count.return_value = 3  # 3 flattened rule-action combinations
    mock_flat_df.printSchema.return_value = None

    # Set up the chain
    mock_raw_df.select.return_value = mock_rules_df
    mock_rules_df.select.return_value = mock_actions_df
    mock_actions_df.select.return_value = mock_flat_df

    return {
        'raw': mock_raw_df,
        'rules': mock_rules_df,
        'actions': mock_actions_df,
        'flat': mock_flat_df
    }


@pytest.fixture
def mock_s3_loader():
    """Create a mock S3Loader for testing."""
    mock_loader = Mock()
    mock_loader.load_df.return_value = None
    return mock_loader


@pytest.fixture
def mock_dbutils():
    """Create a mock dbutils object for Databricks operations."""
    mock_dbutils = Mock()
    mock_dbutils.fs.ls.return_value = []
    return mock_dbutils


@pytest.fixture
def rules_dataframe_schema(spark_session):
    """Create the expected schema for rules DataFrame."""
    return StructType([
        StructField("rule", StructType([
            StructField("rule_id", StringType(), True),
            StructField("status", StringType(), True),
            StructField("scope", StructType([
                StructField("business_context", StringType(), True),
                StructField("category", StringType(), True),
                StructField("company", StringType(), True),
                StructField("context", StringType(), True),
                StructField("cost_center", StringType(), True),
                StructField("journey_step", StringType(), True),
                StructField("line", StringType(), True),
                StructField("profile", StringType(), True),
                StructField("team", StringType(), True),
            ]), True),
            StructField("actions", ArrayType(StructType([
                StructField("action_id", StringType(), True),
                StructField("notification_type", StringType(), True),
                StructField("profile", StringType(), True),
                StructField("reason", StringType(), True),
                StructField("deep_link", StringType(), True),
                StructField("templates", StructType([
                    StructField("subject_template", StringType(), True),
                    StructField("body_template", StringType(), True),
                    StructField("body_template_path", StringType(), True),
                    StructField("subject_content", StringType(), True),
                    StructField("body_content", StringType(), True),
                ]), True),
            ])), True),
        ]), True)
    ])


@pytest.fixture(autouse=True)
def clean_imports():
    """Clean up imports before each test to avoid module caching issues."""
    import sys
    modules_to_remove = [
        mod for mod in sys.modules.keys()
        if mod.startswith('spark_jobs.load_comms_manager_rules')
    ]
    for mod in modules_to_remove:
        del sys.modules[mod]
    yield


# Test utilities
class TestDataFactory:
    """Factory class for creating test data."""

    @staticmethod
    def create_mock_file_info(path: str, modification_time: int):
        """Create a mock file info object."""
        mock_file = Mock()
        mock_file.path = path
        mock_file.modificationTime = modification_time
        return mock_file

    @staticmethod
    def create_sample_rule(rule_id: str, status: str = "active", action_count: int = 1):
        """Create a sample rule with specified parameters."""
        actions = []
        for i in range(action_count):
            actions.append({
                "action_id": f"action_{rule_id}_{i}",
                "notification_type": "email",
                "profile": "tenant",
                "reason": "test",
                "deep_link": f"https://app.com/{rule_id}_{i}",
                "templates": {
                    "subject_template": f"Subject {i}",
                    "body_template": f"Body {i}",
                    "body_template_path": f"/templates/{i}.html",
                    "subject_content": f"Subject Content {i}",
                    "body_content": f"Body Content {i}"
                }
            })

        return {
            "rule_id": rule_id,
            "status": status,
            "scope": {
                "business_context": "test",
                "category": "test",
                "company": "quintoandar",
                "context": "test",
                "cost_center": "test",
                "journey_step": "test",
                "line": "test",
                "profile": "test",
                "team": "test"
            },
            "actions": actions
        }


# Make TestDataFactory available as a fixture
@pytest.fixture
def test_data_factory():
    """Provide access to TestDataFactory."""
    return TestDataFactory
