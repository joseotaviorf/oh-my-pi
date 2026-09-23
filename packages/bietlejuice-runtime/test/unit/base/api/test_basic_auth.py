"""
Unit tests for BasicAuth authentication handler.
"""

import base64
import json
import unittest
from unittest.mock import MagicMock, Mock, patch

import requests

from bietlejuice.base.api.auth.basic import BasicAuth


class TestBasicAuth(unittest.TestCase):
    """Test suite for BasicAuth class."""

    def setUp(self):
        """Sets up the test environment before each test."""
        self.databricks_scope = "PEOPLE"
        self.secret_key = "TEST_SECRET"

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_with_api_token(self, mock_base_dbutils):
        """Test BasicAuth initialization with pre-encoded api_token."""
        api_token = "dXNlcm5hbWU6cGFzc3dvcmQ="  # base64 encoded "username:password"
        secret_data = {"api_token": api_token}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = BasicAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            token_field="api_token",
        )

        self.assertEqual(auth._encoded_token, api_token)
        self.assertEqual(auth.token_field, "api_token")
        self.assertIsNone(auth.username_field)
        self.assertIsNone(auth.password_field)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_with_raw_token(self, mock_base_dbutils):
        """Test BasicAuth encodes a raw token with an empty password."""
        raw_token = "crsr_test_token"
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = raw_token
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = BasicAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
        )

        expected_token = base64.b64encode(f"{raw_token}:".encode()).decode("utf-8")
        self.assertEqual(auth._encoded_token, expected_token)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_with_username_password(self, mock_base_dbutils):
        """Test BasicAuth initialization with username and password."""
        username = "testuser"
        password = "testpass"
        secret_data = {"username": username, "password": password}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = BasicAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            username_field="username",
            password_field="password",
        )

        expected_token = base64.b64encode(f"{username}:{password}".encode()).decode(
            "utf-8"
        )
        self.assertEqual(auth._encoded_token, expected_token)
        self.assertEqual(auth.username_field, "username")
        self.assertEqual(auth.password_field, "password")

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_missing_api_token_raises_error(self, mock_base_dbutils):
        """Test that missing api_token raises ValueError."""
        secret_data = {}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        with self.assertRaises(ValueError) as context:
            BasicAuth(
                databricks_scope=self.databricks_scope,
                secret_key=self.secret_key,
                token_field="api_token",
            )
        self.assertIn("Token field 'api_token' not found", str(context.exception))

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_initialization_missing_username_raises_error(self, mock_base_dbutils):
        """Test that missing username raises ValueError."""
        secret_data = {"password": "testpass"}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        with self.assertRaises(ValueError) as context:
            BasicAuth(
                databricks_scope=self.databricks_scope,
                secret_key=self.secret_key,
                username_field="username",
                password_field="password",
            )
        self.assertIn(
            "Both 'username' and 'password' must be present", str(context.exception)
        )

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_call_applies_basic_auth_header(self, mock_base_dbutils):
        """Test that __call__ applies Basic Auth header to request."""
        api_token = "dXNlcm5hbWU6cGFzc3dvcmQ="
        secret_data = {"api_token": api_token}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance
        auth = BasicAuth(
            databricks_scope=self.databricks_scope, secret_key=self.secret_key
        )
        mock_request = Mock(spec=requests.PreparedRequest)
        mock_request.headers = {}

        result = auth(mock_request)

        self.assertEqual(result.headers["Authorization"], f"Basic {api_token}")
        self.assertEqual(result, mock_request)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_apply_auth_sets_session_auth(self, mock_base_dbutils):
        """Test that apply_auth sets session.auth."""
        api_token = "dXNlcm5hbWU6cGFzc3dvcmQ="
        secret_data = {"api_token": api_token}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance
        auth = BasicAuth(
            databricks_scope=self.databricks_scope, secret_key=self.secret_key
        )
        mock_session = Mock(spec=requests.Session)

        auth.apply_auth(mock_session)

        self.assertEqual(mock_session.auth, auth)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_custom_token_field(self, mock_base_dbutils):
        """Test BasicAuth with custom token field name."""
        custom_token = "Y3VzdG9tX3Rva2Vu"  # base64 encoded "custom_token"
        secret_data = {"custom_token_field": custom_token}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = BasicAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            token_field="custom_token_field",
        )

        self.assertEqual(auth._encoded_token, custom_token)

    @patch("bietlejuice.base.api.auth.base.BaseDBUtils")
    def test_username_password_encoding(self, mock_base_dbutils):
        """Test that username:password is correctly Base64 encoded."""
        username = "user@example.com"
        password = "secret123"
        secret_data = {"username": username, "password": password}
        mock_dbutils_instance = MagicMock()
        mock_dbutils_instance.secrets.get.return_value = json.dumps(secret_data)
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils_instance

        auth = BasicAuth(
            databricks_scope=self.databricks_scope,
            secret_key=self.secret_key,
            username_field="username",
            password_field="password",
        )

        expected_encoded = base64.b64encode(f"{username}:{password}".encode()).decode(
            "utf-8"
        )
        self.assertEqual(auth._encoded_token, expected_encoded)
