import unittest
from unittest.mock import MagicMock, patch

import requests
from requests.exceptions import RequestException

from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.common.exceptions import (
    APIException,
    BadRequestError,
    NotFoundError,
    RateLimitError,
)


class TestBaseAPIClient(unittest.TestCase):
    def setUp(self):
        """Set up the test client and mock session."""
        self.base_url = "http://fakeapi.com"
        self.client = BaseAPIClient(base_url=self.base_url)
        self.mock_session_patch = patch(
            "bietlejuice.base.api.common.client.requests.Session"
        )
        self.mock_session = self.mock_session_patch.start()
        self.client.session = self.mock_session

    def tearDown(self):
        """Stop the patcher."""
        self.mock_session_patch.stop()

    def test_get_successful_request(self):
        """Test a successful GET request."""
        mock_response = MagicMock(
            status_code=200, json=MagicMock(return_value={"data": "success"})
        )
        mock_response.raise_for_status.return_value = None
        self.client.session.get.return_value = mock_response

        endpoint = "/test"
        response = self.client.get(endpoint)

        self.client.session.get.assert_called_once_with(
            f"{self.base_url}{endpoint}", params=None, headers=None, timeout=30
        )
        self.assertEqual(response, mock_response)

    def test_get_with_params(self):
        """Test a GET request with query parameters."""
        mock_response = MagicMock(status_code=200)
        mock_response.raise_for_status.return_value = None
        self.client.session.get.return_value = mock_response

        endpoint = "/search"
        params = {"query": "test"}
        self.client.get(endpoint, params=params)

        self.client.session.get.assert_called_once_with(
            f"{self.base_url}{endpoint}", params=params, headers=None, timeout=30
        )

    def test_handle_http_exceptions(self):
        """Test handling of specific HTTP error codes."""
        error_cases = [
            (400, "Invalid parameter", BadRequestError),
            (404, "Resource not found", NotFoundError),
            (429, "Too Many Requests", RateLimitError),
        ]

        for status_code, text, expected_exception in error_cases:
            with self.subTest(
                status_code=status_code, exception=expected_exception.__name__
            ):
                mock_response = MagicMock(status_code=status_code, text=text)
                self.client.session.get.return_value = mock_response

                with self.assertRaises(expected_exception):
                    self.client.get(f"/test_{status_code}")

    def test_handle_request_exception(self):
        """Test handling of a generic RequestException."""
        self.client.session.get.side_effect = RequestException("Connection error")

        with self.assertRaises(APIException):
            self.client.get("/request_exception")

    def test_raise_for_status_other_error(self):
        """Test that other HTTP errors are raised by raise_for_status."""
        mock_response = MagicMock(status_code=503)
        mock_response.raise_for_status.side_effect = requests.HTTPError
        self.client.session.get.return_value = mock_response

        with self.assertRaises(requests.HTTPError):
            self.client._handle_response(mock_response)


class TestFormatIsoTimestamp(unittest.TestCase):
    """Tests for the BaseAPIClient.format_iso_timestamp static method."""

    def test_format_date_string_without_time(self):
        """Test formatting a date string without time component."""
        result = BaseAPIClient.format_iso_timestamp("2025-10-16")
        self.assertEqual(result, "2025-10-16T00:00:00.000Z")

    def test_format_date_string_with_custom_time_suffix(self):
        """Test formatting a date string with custom time suffix."""
        result = BaseAPIClient.format_iso_timestamp("2025-10-16", "T23:59:59.999Z")
        self.assertEqual(result, "2025-10-16T23:59:59.999Z")

    def test_format_datetime_string_without_z(self):
        """Test formatting a datetime string without Z suffix."""
        result = BaseAPIClient.format_iso_timestamp("2025-10-16T10:30:00")
        self.assertEqual(result, "2025-10-16T10:30:00Z")

    def test_format_datetime_string_with_z(self):
        """Test formatting a datetime string that already has Z suffix."""
        result = BaseAPIClient.format_iso_timestamp("2025-10-16T10:30:00Z")
        self.assertEqual(result, "2025-10-16T10:30:00Z")

    def test_format_datetime_string_with_space_separator(self):
        """Test formatting a datetime string with space separator."""
        result = BaseAPIClient.format_iso_timestamp("2025-10-16 10:30:00")
        self.assertEqual(result, "2025-10-16T10:30:00Z")

    def test_format_datetime_string_with_milliseconds(self):
        """Test formatting a datetime string with milliseconds."""
        result = BaseAPIClient.format_iso_timestamp("2025-10-16T10:30:00.123")
        self.assertEqual(result, "2025-10-16T10:30:00.123Z")

    def test_format_datetime_object(self):
        """Test formatting a datetime object."""
        from datetime import datetime

        dt = datetime(2025, 10, 16, 10, 30, 0, 123000)
        result = BaseAPIClient.format_iso_timestamp(dt)
        self.assertEqual(result, "2025-10-16T10:30:00.123Z")

    def test_format_date_object(self):
        """Test formatting a date object."""
        from datetime import date

        d = date(2025, 10, 16)
        result = BaseAPIClient.format_iso_timestamp(d)
        self.assertEqual(result, "2025-10-16T00:00:00.000Z")

    def test_format_date_object_with_custom_suffix(self):
        """Test formatting a date object with custom time suffix."""
        from datetime import date

        d = date(2025, 10, 16)
        result = BaseAPIClient.format_iso_timestamp(d, "T23:59:59.999Z")
        self.assertEqual(result, "2025-10-16T23:59:59.999Z")
