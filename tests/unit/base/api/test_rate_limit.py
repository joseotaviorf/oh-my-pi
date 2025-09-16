import unittest
from unittest.mock import MagicMock, patch
import requests

from bietlejuice.base.api.rate_limit.header_adapter import HeaderRateLimitAdapter


class TestHeaderRateLimitAdapter(unittest.TestCase):
    def setUp(self):
        """Sets up the test environment before each test."""
        self.adapter = HeaderRateLimitAdapter(min_remaining_threshold=5)
        self.mock_super_send = patch.object(
            requests.adapters.HTTPAdapter, "send", autospec=True
        )
        self.mock_send = self.mock_super_send.start()

    def tearDown(self):
        """Stops the patcher."""
        self.mock_super_send.stop()

    @patch("time.sleep")
    @patch("time.time")
    def test_wait_if_needed_proactive_wait(self, mock_time, mock_sleep):
        """Tests proactive waiting when the remaining request limit is reached."""
        mock_time.return_value = 1000.0
        self.adapter.rate_limit_remaining = 4
        self.adapter.rate_limit_reset_time = 1010.0

        self.adapter._wait_if_needed()

        mock_sleep.assert_called_once()
        self.assertAlmostEqual(mock_sleep.call_args[0][0], 10.1)

    @patch("time.sleep")
    @patch("time.time")
    def test_wait_if_needed_no_wait(self, mock_time, mock_sleep):
        """Tests that there is no waiting if the remaining request limit is above the threshold."""
        mock_time.return_value = 1000.0
        self.adapter.rate_limit_remaining = 10
        self.adapter.rate_limit_reset_time = 1010.0

        self.adapter._wait_if_needed()

        mock_sleep.assert_not_called()

    def test_update_rate_limit_from_headers_unix_timestamp(self):
        """Tests updating the rate limit from a Unix timestamp."""
        headers = {"X-RateLimit-Remaining": "100", "X-RateLimit-Reset": "1700000000"}

        self.adapter._update_rate_limit_from_headers(headers)

        self.assertEqual(self.adapter.rate_limit_remaining, 100)
        self.assertEqual(self.adapter.rate_limit_reset_time, 1700000000)

    @patch("time.time")
    def test_update_rate_limit_from_headers_relative_seconds(self, mock_time):
        """Tests updating the rate limit from relative seconds."""
        mock_time.return_value = 1000.0
        headers = {"X-RateLimit-Remaining": "50", "X-RateLimit-Reset": "60"}

        self.adapter._update_rate_limit_from_headers(headers)

        self.assertEqual(self.adapter.rate_limit_remaining, 50)
        self.assertEqual(self.adapter.rate_limit_reset_time, 1060.0)

    @patch("time.sleep")
    def test_send_handles_429_with_retry_after(self, mock_sleep):
        """Tests reactive handling of a 429 response with a Retry-After header."""
        mock_request = requests.PreparedRequest()

        mock_response_429 = MagicMock(spec=requests.Response)
        mock_response_429.status_code = 429
        mock_response_429.headers = {"Retry-After": "5"}

        mock_response_200 = MagicMock(spec=requests.Response)
        mock_response_200.status_code = 200
        mock_response_200.headers = {}

        self.mock_send.side_effect = [mock_response_429, mock_response_200]

        response = self.adapter.send(mock_request)

        self.assertEqual(self.mock_send.call_count, 2)
        mock_sleep.assert_called_once_with(5)
        self.assertEqual(response, mock_response_200)
