"""
Unit tests for APIKeyAuth authentication handler.
"""

import json
import unittest
from unittest.mock import MagicMock, Mock, patch

import requests

from bietlejuice.base.api.auth.api_key import APIKeyAuth


class TestAPIKeyAuth(unittest.TestCase):
    """Test suite for APIKeyAuth class."""

    def setUp(self):
        """Sets up the test environment before each test."""
        self.databricks_scope = "PEOPLE"
        self.secret_key = "TEST_SECRET"

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_with_default_api_key_field(self, mock_base_dbutils):
        """Test APIKeyAuth initialization with default api_key field."""
        api_key = "test-api-key-123"
        secret_data = {"api_key": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
        )

        self.assertEqual(auth._api_key, api_key)
        self.assertEqual(auth.api_key_field, "api_key")
        self.assertEqual(auth.location, "header")
        self.assertEqual(auth.header_name, "x-api-key")
        self.assertEqual(auth.query_param_name, "token")

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_with_custom_api_key_field(self, mock_base_dbutils):
        """Test APIKeyAuth initialization with custom api_key field name."""
        api_key = "custom-key-value"
        secret_data = {"custom_key_field": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            api_key_field="custom_key_field",
        )

        self.assertEqual(auth._api_key, api_key)
        self.assertEqual(auth.api_key_field, "custom_key_field")

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_missing_api_key_raises_error(self, mock_base_dbutils):
        """Test that missing api_key raises ValueError."""
        secret_data = {}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        with self.assertRaises(ValueError) as context:
            APIKeyAuth(
                databricks_scope=self.databricks_scope,
                secret_key=self.secret_key,
            )
        self.assertIn(
            "API key field 'api_key' not found in secret",
            str(context.exception),
        )

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_call_applies_api_key_as_header(self, mock_base_dbutils):
        """Test that __call__ applies API key as header when location is header."""
        api_key = "header-api-key"
        secret_data = {"api_key": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            location="header",
        )
        mock_request = Mock(spec=requests.PreparedRequest)
        mock_request.headers = {}
        mock_request.url = "https://api.example.com/endpoint"

        result = auth(mock_request)

        self.assertEqual(result.headers["x-api-key"], api_key)
        self.assertEqual(result, mock_request)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_call_applies_api_key_as_query_param(self, mock_base_dbutils):
        """Test that __call__ applies API key as query param when location is query_param."""
        api_key = "query-api-key"
        secret_data = {"api_key": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            location="query_param",
        )
        mock_request = Mock(spec=requests.PreparedRequest)
        mock_request.headers = {}
        mock_request.url = "https://api.example.com/endpoint"

        result = auth(mock_request)

        self.assertIn("token=" + api_key, result.url)
        self.assertEqual(result, mock_request)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_call_with_custom_header_name(self, mock_base_dbutils):
        """Test that __call__ uses custom header name when specified."""
        api_key = "custom-header-key"
        secret_data = {"api_key": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            header_name="Authorization",
        )
        mock_request = Mock(spec=requests.PreparedRequest)
        mock_request.headers = {}
        mock_request.url = "https://api.example.com/endpoint"

        result = auth(mock_request)

        self.assertEqual(result.headers["Authorization"], api_key)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_call_with_custom_query_param_name(self, mock_base_dbutils):
        """Test that __call__ uses custom query param name when specified."""
        api_key = "custom-param-key"
        secret_data = {"api_key": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            location="query_param",
            query_param_name="api_key",
        )
        mock_request = Mock(spec=requests.PreparedRequest)
        mock_request.headers = {}
        mock_request.url = "https://api.example.com/endpoint"

        result = auth(mock_request)

        self.assertIn("api_key=" + api_key, result.url)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_call_invalid_location_raises_error(self, mock_base_dbutils):
        """Test that invalid location raises ValueError."""
        api_key = "test-key"
        secret_data = {"api_key": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            location="invalid",
        )
        auth._api_key = api_key
        mock_request = Mock(spec=requests.PreparedRequest)
        mock_request.headers = {}
        mock_request.url = "https://api.example.com/endpoint"

        with self.assertRaises(ValueError) as context:
            auth(mock_request)
        self.assertIn("not supported", str(context.exception))

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_apply_auth_sets_session_auth(self, mock_base_dbutils):
        """Test that apply_auth sets session.auth."""
        api_key = "session-key"
        secret_data = {"api_key": api_key}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = APIKeyAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
        )
        mock_session = Mock(spec=requests.Session)

        auth.apply_auth(mock_session)

        self.assertEqual(mock_session.auth, auth)
