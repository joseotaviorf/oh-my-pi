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
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {"data": "success"}
        self.client.session.get.return_value = mock_response

        endpoint = "/test"
        response = self.client.get(endpoint)

        self.client.session.get.assert_called_once_with(
            f"{self.base_url}{endpoint}", params=None, timeout=30
        )
        self.assertEqual(response, mock_response)

    def test_get_with_params(self):
        """Test a GET request with query parameters."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.raise_for_status.return_value = None
        self.client.session.get.return_value = mock_response

        endpoint = "/search"
        params = {"query": "test"}
        self.client.get(endpoint, params=params)

        self.client.session.get.assert_called_once_with(
            f"{self.base_url}{endpoint}", params=params, timeout=30
        )

    def test_handle_bad_request_exception(self):
        """Test handling of a 400 Bad Request error."""
        mock_response = MagicMock()
        mock_response.status_code = 400
        mock_response.text = "Invalid parameter"
        self.client.session.get.return_value = mock_response

        with self.assertRaises(BadRequestError):
            self.client.get("/bad_request")

    def test_handle_not_found_exception(self):
        """Test handling of a 404 Not Found error."""
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_response.text = "Resource does not exist"
        self.client.session.get.return_value = mock_response

        with self.assertRaises(NotFoundError):
            self.client.get("/not_found")

    def test_handle_rate_limit_exception(self):
        """Test handling of a 429 Rate Limit Exceeded error."""
        mock_response = MagicMock()
        mock_response.status_code = 429
        self.client.session.get.return_value = mock_response

        with self.assertRaises(RateLimitError):
            self.client.get("/rate_limit")

    def test_handle_request_exception(self):
        """Test handling of a generic RequestException."""
        self.client.session.get.side_effect = RequestException("Connection error")

        with self.assertRaises(APIException):
            self.client.get("/request_exception")

    def test_raise_for_status_other_error(self):
        """Test that other HTTP errors are raised by raise_for_status."""
        mock_response = MagicMock()
        mock_response.status_code = 503
        mock_response.raise_for_status.side_effect = requests.HTTPError
        self.client.session.get.return_value = mock_response

        with self.assertRaises(requests.HTTPError):
            self.client._handle_response(mock_response)
