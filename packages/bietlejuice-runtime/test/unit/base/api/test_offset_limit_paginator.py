"""
Unit tests for OffsetLimitPaginator.
"""

import unittest
from unittest.mock import MagicMock, Mock

from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.pagination.offset_limit import OffsetLimitPaginator


class TestOffsetLimitPaginator(unittest.TestCase):
    """Test suite for OffsetLimitPaginator class."""

    def setUp(self):
        """Sets up the test environment before each test."""
        self.mock_client = MagicMock(spec=BaseAPIClient)
        self.mock_client.base_url = "http://fakeapi.com"
        self.endpoint = "workers"

    def test_initialization_with_defaults(self):
        """Test that paginator is initialized correctly with default values."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint)

        self.assertEqual(paginator.client, self.mock_client)
        self.assertEqual(paginator.endpoint, self.endpoint)
        self.assertEqual(paginator.limit_param, "limit")
        self.assertEqual(paginator.offset_param, "offset")
        self.assertEqual(paginator.page_size, 100)
        self.assertIsNone(paginator.page_delay)

    def test_initialization_with_custom_params(self):
        """Test initialization with custom parameters."""
        paginator = OffsetLimitPaginator(
            self.mock_client,
            self.endpoint,
            limit_param="count",
            offset_param="start",
            page_size=50,
            page_delay=2.0,
        )

        self.assertEqual(paginator.limit_param, "count")
        self.assertEqual(paginator.offset_param, "start")
        self.assertEqual(paginator.page_size, 50)
        self.assertEqual(paginator.page_delay, 2.0)

    def test_default_extract_results_from_list(self):
        """Test default extract_results with list response."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint)
        response_data = [{"id": 1}, {"id": 2}]

        results = paginator.extract_results(response_data)

        self.assertEqual(results, [{"id": 1}, {"id": 2}])

    def test_default_extract_results_from_dict_with_items(self):
        """Test default extract_results with dict containing 'items' key."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint)
        response_data = {"items": [{"id": 1}, {"id": 2}]}

        results = paginator.extract_results(response_data)

        self.assertEqual(results, [{"id": 1}, {"id": 2}])

    def test_default_extract_results_from_dict_with_results(self):
        """Test default extract_results with dict containing 'results' key."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint)
        response_data = {"results": [{"id": 1}, {"id": 2}]}

        results = paginator.extract_results(response_data)

        self.assertEqual(results, [{"id": 1}, {"id": 2}])

    def test_default_is_last_page_empty_results(self):
        """Test that empty results indicate last page."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint)
        response_data = {}
        results = []

        is_last = paginator.is_last_page(response_data, results)

        self.assertTrue(is_last)

    def test_default_is_last_page_fewer_results_than_page_size(self):
        """Test that fewer results than page_size indicate last page."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint, page_size=100)
        response_data = {}
        results = [{"id": i} for i in range(50)]  # Only 50 results

        is_last = paginator.is_last_page(response_data, results)

        self.assertTrue(is_last)

    def test_default_is_last_page_full_page_size(self):
        """Test that full page_size results indicate more pages available."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint, page_size=100)
        response_data = {}
        results = [{"id": i} for i in range(100)]  # Exactly 100 results

        is_last = paginator.is_last_page(response_data, results)

        self.assertFalse(is_last)

    def test_fetch_all_single_page(self):
        """Test fetching data when there is only one page."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint, page_size=100)
        mock_response = MagicMock()
        mock_response.json.return_value = {"items": [{"id": 1}, {"id": 2}]}
        mock_response.raise_for_status = Mock(
            side_effect=AssertionError(
                "Paginator should not call response.raise_for_status()"
            )
        )
        self.mock_client.get.return_value = mock_response

        all_pages = list(paginator.fetch_all())

        self.assertEqual(len(all_pages), 1)
        self.assertEqual(all_pages[0], [{"id": 1}, {"id": 2}])
        self.mock_client.get.assert_called_once()
        call_args = self.mock_client.get.call_args
        self.assertEqual(call_args[1]["params"]["offset"], 0)
        self.assertEqual(call_args[1]["params"]["limit"], 100)

    def test_fetch_all_multiple_pages(self):
        """Test fetching data from multiple pages."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint, page_size=2)

        mock_response_1 = MagicMock()
        mock_response_1.json.return_value = {"items": [{"id": 1}, {"id": 2}]}
        mock_response_1.raise_for_status = Mock(
            side_effect=AssertionError(
                "Paginator should not call response.raise_for_status()"
            )
        )

        mock_response_2 = MagicMock()
        mock_response_2.json.return_value = {"items": [{"id": 3}, {"id": 4}]}
        mock_response_2.raise_for_status = Mock(
            side_effect=AssertionError(
                "Paginator should not call response.raise_for_status()"
            )
        )

        mock_response_3 = MagicMock()
        mock_response_3.json.return_value = {"items": [{"id": 5}]}
        mock_response_3.raise_for_status = Mock(
            side_effect=AssertionError(
                "Paginator should not call response.raise_for_status()"
            )
        )

        captured_offsets = []

        def capture_call(*args, **kwargs):
            """Capture offset value at the time of the call."""
            offset_value = kwargs.get("params", {}).get("offset")
            captured_offsets.append(offset_value)
            response_idx = len(captured_offsets) - 1
            responses = [mock_response_1, mock_response_2, mock_response_3]
            return responses[response_idx]

        self.mock_client.get.side_effect = capture_call

        all_pages = list(paginator.fetch_all())

        self.assertEqual(len(all_pages), 3)
        self.assertEqual(all_pages[0], [{"id": 1}, {"id": 2}])
        self.assertEqual(all_pages[1], [{"id": 3}, {"id": 4}])
        self.assertEqual(all_pages[2], [{"id": 5}])
        self.assertEqual(self.mock_client.get.call_count, 3)

        self.assertEqual(captured_offsets[0], 0)
        self.assertEqual(captured_offsets[1], 2)
        self.assertEqual(captured_offsets[2], 4)

    def test_fetch_all_with_initial_params(self):
        """Test that initial params are preserved and merged with pagination params."""
        initial_params = {"onlyData": True, "orderBy": "PersonId:asc"}
        paginator = OffsetLimitPaginator(
            self.mock_client,
            self.endpoint,
            initial_params=initial_params,
            page_size=100,
        )
        mock_response = MagicMock()
        mock_response.json.return_value = {"items": []}
        mock_response.raise_for_status = Mock()
        self.mock_client.get.return_value = mock_response

        list(paginator.fetch_all())

        call_args = self.mock_client.get.call_args
        params = call_args[1]["params"]
        self.assertEqual(params["onlyData"], True)
        self.assertEqual(params["orderBy"], "PersonId:asc")
        self.assertEqual(params["offset"], 0)
        self.assertEqual(params["limit"], 100)

    def test_fetch_all_with_empty_results_stops(self):
        """Test that pagination stops when results are empty."""
        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint, page_size=100)
        mock_response = MagicMock()
        mock_response.json.return_value = {"items": []}
        mock_response.raise_for_status = Mock()
        self.mock_client.get.return_value = mock_response

        all_pages = list(paginator.fetch_all())

        self.assertEqual(len(all_pages), 0)
        self.mock_client.get.assert_called_once()

    def test_fetch_all_handles_api_error(self):
        """Test that API errors are raised."""
        from bietlejuice.base.api.common.exceptions import APIException

        paginator = OffsetLimitPaginator(self.mock_client, self.endpoint)
        self.mock_client.get.side_effect = APIException("API Error", status_code=500)

        with self.assertRaises(APIException):
            list(paginator.fetch_all())