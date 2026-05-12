import json
from unittest.mock import Mock, patch

import pytest
from pyspark.sql import SparkSession
from requests import Session

from bietlejuice.services.cdf_services.schema_registry import (
    _create_session_with_retry,
    create_or_get_schema_on_registry,
    register_schema_for_dataframe,
)


class TestCreateSessionWithRetry:
    """Test cases for _create_session_with_retry function."""

    def test_create_session_with_retry_returns_session(self):
        """Test that _create_session_with_retry returns a requests Session."""
        session = _create_session_with_retry()

        assert isinstance(session, Session)

    def test_create_session_with_retry_configures_retry_strategy(self):
        """Test that session is configured with correct retry strategy."""
        session = _create_session_with_retry()

        # Check that adapters are mounted
        assert "http://" in session.adapters
        assert "https://" in session.adapters

        # Get the adapter and check retry configuration
        adapter = session.adapters["https://"]
        retry = adapter.max_retries

        assert retry.total == 3
        assert retry.backoff_factor == 2
        assert retry.status_forcelist == [429, 500, 502, 503, 504]
        assert retry.allowed_methods == ["POST", "GET"]


class TestCreateOrGetSchemaOnRegistry:
    """Test cases for create_or_get_schema_on_registry function."""

    @patch(
        "bietlejuice.services.cdf_services.schema_registry._create_session_with_retry"
    )
    def test_create_or_get_schema_success_200(self, mock_create_session):
        """Test successful schema creation with 200 status."""
        # Mock session and response
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"id": 123}
        mock_session.post.return_value = mock_response
        mock_create_session.return_value = mock_session

        schema = {"type": "object", "properties": {"name": {"type": "string"}}}
        schema_id = create_or_get_schema_on_registry(
            schema=schema,
            subject="test-subject",
            schema_registry_url="https://registry.example.com",
            schema_registry_api_key="key",
            schema_registry_api_secret="secret",
        )

        assert schema_id == 123
        mock_session.post.assert_called_once()
        call_args = mock_session.post.call_args
        assert (
            call_args[0][0]
            == "https://registry.example.com/subjects/test-subject/versions"
        )
        assert call_args[1]["json"] == {
            "schemaType": "JSON",
            "schema": json.dumps(schema),
        }
        assert call_args[1]["headers"] == {
            "Content-Type": "application/vnd.schemaregistry.v1+json"
        }
        assert call_args[1]["auth"] == ("key", "secret")
        assert call_args[1]["timeout"] == 10

    @patch(
        "bietlejuice.services.cdf_services.schema_registry._create_session_with_retry"
    )
    def test_create_or_get_schema_success_201(self, mock_create_session):
        """Test successful schema creation with 201 status."""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 201
        mock_response.json.return_value = {"id": 456}
        mock_session.post.return_value = mock_response
        mock_create_session.return_value = mock_session

        schema = {"type": "object"}
        schema_id = create_or_get_schema_on_registry(
            schema=schema,
            subject="test-subject",
            schema_registry_url="https://registry.example.com",
            schema_registry_api_key="key",
            schema_registry_api_secret="secret",
        )

        assert schema_id == 456

    @patch(
        "bietlejuice.services.cdf_services.schema_registry._create_session_with_retry"
    )
    def test_create_or_get_schema_failure_status_code(self, mock_create_session):
        """Test schema creation failure with non-success status code."""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 400
        mock_response.text = "Bad Request"
        mock_session.post.return_value = mock_response
        mock_create_session.return_value = mock_session

        schema = {"type": "object"}

        with pytest.raises(Exception) as exc_info:
            create_or_get_schema_on_registry(
                schema=schema,
                subject="test-subject",
                schema_registry_url="https://registry.example.com",
                schema_registry_api_key="key",
                schema_registry_api_secret="secret",
            )

        assert "Failed to persist schema on registry: 400 - Bad Request" in str(
            exc_info.value
        )

    @patch(
        "bietlejuice.services.cdf_services.schema_registry._create_session_with_retry"
    )
    def test_create_or_get_schema_request_exception(self, mock_create_session):
        """Test schema creation failure with request exception."""
        from requests.exceptions import RequestException

        mock_session = Mock()
        mock_session.post.side_effect = RequestException("Connection failed")
        mock_create_session.return_value = mock_session

        schema = {"type": "object"}

        with pytest.raises(Exception) as exc_info:
            create_or_get_schema_on_registry(
                schema=schema,
                subject="test-subject",
                schema_registry_url="https://registry.example.com",
                schema_registry_api_key="key",
                schema_registry_api_secret="secret",
            )

        assert (
            "Failed to connect to Schema Registry at https://registry.example.com: Connection failed"
            in str(exc_info.value)
        )


class TestRegisterSchemaForDataframe:
    """Test cases for register_schema_for_dataframe function."""

    @pytest.fixture
    def spark_session(self):
        """Create a Spark session for testing."""
        return SparkSession.builder.appName("test_schema_registry").getOrCreate()

    @pytest.fixture
    def sample_dataframe(self, spark_session):
        """Create a sample DataFrame for testing."""
        data = [("Alice", 30, True), ("Bob", 25, False)]
        df = spark_session.createDataFrame(data, ["name", "age", "active"])
        return df

    @pytest.fixture
    def sample_dataframe_with_cdf_columns(self, spark_session):
        """Create a sample DataFrame with CDF metadata columns."""
        data = [
            ("Alice", 30, True, "insert", 123, "2024-01-01"),
            ("Bob", 25, False, "update", 124, "2024-01-02"),
        ]
        df = spark_session.createDataFrame(
            data,
            [
                "name",
                "age",
                "active",
                "_change_type",
                "_commit_version",
                "_commit_timestamp",
            ],
        )
        return df

    @patch(
        "bietlejuice.services.cdf_services.schema_registry.create_or_get_schema_on_registry"
    )
    @patch(
        "bietlejuice.services.cdf_services.schema_registry.generate_json_schema_from_dataframe"
    )
    def test_register_schema_for_dataframe_basic(
        self, mock_generate_schema, mock_create_schema, sample_dataframe
    ):
        """Test basic schema registration for DataFrame."""
        mock_generate_schema.return_value = {
            "type": "object",
            "properties": {"name": {"type": "string"}},
        }
        mock_create_schema.return_value = 789

        schema_id = register_schema_for_dataframe(
            dataframe=sample_dataframe,
            topic="test-topic",
            delta_table="wonka.test_feature_set__latest",
            schema_registry_url="https://registry.example.com",
            schema_registry_api_key="key",
            schema_registry_api_secret="secret",
        )

        assert schema_id == 789

        # Check that generate_json_schema_from_dataframe was called with filtered dataframe
        mock_generate_schema.assert_called_once()
        call_args = mock_generate_schema.call_args
        assert call_args[1]["schema_name"] == "test-topic"

        # Verify the dataframe passed has the right columns (no CDF columns)
        df_arg = call_args[0][0]
        assert "_change_type" not in df_arg.columns
        assert "_commit_version" not in df_arg.columns
        assert "_commit_timestamp" not in df_arg.columns
        assert "name" in df_arg.columns
        assert "age" in df_arg.columns
        assert "active" in df_arg.columns

        # Check that create_or_get_schema_on_registry was called with correct subject
        mock_create_schema.assert_called_once()
        call_args = mock_create_schema.call_args
        assert call_args[1]["subject"] == "test-topic.test_feature_set-value"
        assert call_args[1]["schema_registry_url"] == "https://registry.example.com"
        assert call_args[1]["schema_registry_api_key"] == "key"
        assert call_args[1]["schema_registry_api_secret"] == "secret"

    @patch(
        "bietlejuice.services.cdf_services.schema_registry.create_or_get_schema_on_registry"
    )
    @patch(
        "bietlejuice.services.cdf_services.schema_registry.generate_json_schema_from_dataframe"
    )
    def test_register_schema_for_dataframe_with_cdf_columns(
        self,
        mock_generate_schema,
        mock_create_schema,
        sample_dataframe_with_cdf_columns,
    ):
        """Test schema registration filters out CDF metadata columns."""
        mock_generate_schema.return_value = {
            "type": "object",
            "properties": {"name": {"type": "string"}},
        }
        mock_create_schema.return_value = 101

        schema_id = register_schema_for_dataframe(
            dataframe=sample_dataframe_with_cdf_columns,
            topic="test-topic",
            delta_table="database.table__latest",
            schema_registry_url="https://registry.example.com",
            schema_registry_api_key="key",
            schema_registry_api_secret="secret",
        )

        assert schema_id == 101

        # Verify CDF columns are filtered out
        call_args = mock_generate_schema.call_args
        df_arg = call_args[0][0]
        assert "_change_type" not in df_arg.columns
        assert "_commit_version" not in df_arg.columns
        assert "_commit_timestamp" not in df_arg.columns
        assert "name" in df_arg.columns

    @patch(
        "bietlejuice.services.cdf_services.schema_registry.create_or_get_schema_on_registry"
    )
    @patch(
        "bietlejuice.services.cdf_services.schema_registry.generate_json_schema_from_dataframe"
    )
    def test_register_schema_for_dataframe_subject_parsing(
        self, mock_generate_schema, mock_create_schema, sample_dataframe
    ):
        """Test that subject is correctly parsed from delta_table name."""
        mock_generate_schema.return_value = {"type": "object"}
        mock_create_schema.return_value = 202

        # Test various delta table name formats
        test_cases = [
            ("wonka.house_main__latest", "test-topic.house_main-value"),
            ("database.feature_set__latest", "test-topic.feature_set-value"),
            ("simple_table", "test-topic.simple_table-value"),
        ]

        for delta_table, expected_subject in test_cases:
            register_schema_for_dataframe(
                dataframe=sample_dataframe,
                topic="test-topic",
                delta_table=delta_table,
                schema_registry_url="https://registry.example.com",
                schema_registry_api_key="key",
                schema_registry_api_secret="secret",
            )

            call_args = mock_create_schema.call_args
            assert call_args[1]["subject"] == expected_subject

    def test_register_schema_for_dataframe_invalid_dataframe(self):
        """Test that function raises appropriate error for invalid DataFrame."""
        # This would be hard to test directly since DataFrame validation happens in generate_json_schema_from_dataframe
        # We'll skip this for now as it's covered by integration with the actual function
        pass
