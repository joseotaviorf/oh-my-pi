import unittest
from unittest.mock import MagicMock

import requests

from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.pagination.cursor import CursorPaginator


class TestCursorPaginator(unittest.TestCase):
    def setUp(self):
        """Sets up the test environment before each test."""
        self.mock_client = MagicMock(spec=BaseAPIClient)
        self.mock_client.base_url = "http://fakeapi.com"
        self.mock_client.session = MagicMock()
        self.mock_client.timeout = 30

    def test_initialization_with_defaults(self):
        """Tests if the paginator is initialized correctly with default values."""
        endpoint = "items"
        paginator = CursorPaginator(self.mock_client, endpoint)

        self.assertEqual(paginator.client, self.mock_client)
        self.assertEqual(paginator.endpoint, endpoint)
        self.assertEqual(paginator.cursor_param, "cursor")
        self.assertEqual(paginator.cursor_location, "param")
        self.assertEqual(paginator.cursor_response_path, "next_cursor")
        self.assertIsNone(paginator.context_param)

    def test_initialization_with_custom_params(self):
        """Tests initialization with custom parameters."""
        endpoint = "events"
        paginator = CursorPaginator(
            self.mock_client,
            endpoint,
            cursor_param="Search-After",
            cursor_location="header",
            cursor_response_path="paging.next_search_after",
            context_param="Pit-Id",
            context_location="header",
            context_response_path="paging.pit_id",
            page_size_param="Size",
            page_size_location="header",
            page_size=500,
        )

        self.assertEqual(paginator.cursor_param, "Search-After")
        self.assertEqual(paginator.cursor_location, "header")
        self.assertEqual(paginator.context_param, "Pit-Id")
        self.assertEqual(paginator.page_size, 500)

    def test_default_extract_results_common_keys(self):
        """Tests the default extract_results method with various common keys."""
        paginator = CursorPaginator(self.mock_client, "items")
        expected_results = [{"id": 1}, {"id": 2}]

        # List of scenarios to test
        test_cases = [
            {"results": expected_results},
            {"items": expected_results},
            {"data": expected_results},
            {"records": expected_results},
        ]

        for i, response_data in enumerate(test_cases):
            key = list(response_data.keys())[0]
            with self.subTest(f"Testing response with key '{key}'", i=i):
                results = paginator.extract_results(response_data)
                self.assertEqual(results, expected_results)

    def test_default_extract_results_as_list(self):
        """Tests the default extract_results when response is a list."""
        paginator = CursorPaginator(self.mock_client, "items")
        response_data = [{"id": 1}, {"id": 2}]
        results = paginator.extract_results(response_data)
        self.assertEqual(results, [{"id": 1}, {"id": 2}])

    def test_custom_extract_results(self):
        """Tests using a custom extract_results function."""

        def custom_extractor(data):
            return data.get("custom_field", [])

        paginator = CursorPaginator(
            self.mock_client, "items", extract_results=custom_extractor
        )
        response_data = {"custom_field": [{"id": 1}]}
        results = paginator.extract_results(response_data)
        self.assertEqual(results, [{"id": 1}])

    def test_extract_pagination_state_simple_cursor(self):
        """Tests extracting pagination state with simple cursor path."""
        paginator = CursorPaginator(
            self.mock_client, "items", cursor_response_path="next_cursor"
        )
        response_data = {"next_cursor": "abc123"}
        state = paginator.extract_pagination_state(response_data)
        self.assertEqual(state, {"cursor": "abc123"})

    def test_extract_pagination_state_nested_cursor(self):
        """Tests extracting pagination state with nested cursor path."""
        paginator = CursorPaginator(
            self.mock_client, "items", cursor_response_path="paging.next_search_after"
        )
        response_data = {"paging": {"next_search_after": "xyz789"}}
        state = paginator.extract_pagination_state(response_data)
        self.assertEqual(state, {"cursor": "xyz789"})

    def test_extract_pagination_state_with_context(self):
        """Tests extracting pagination state with both cursor and context."""
        paginator = CursorPaginator(
            self.mock_client,
            "items",
            cursor_response_path="paging.next_search_after",
            context_param="Pit-Id",
            context_response_path="paging.pit_id",
        )
        response_data = {"paging": {"next_search_after": "xyz789", "pit_id": "pit123"}}
        state = paginator.extract_pagination_state(response_data)
        self.assertEqual(state, {"cursor": "xyz789", "context": "pit123"})

    def test_is_last_page_no_cursor(self):
        """Tests is_last_page when cursor is None."""
        paginator = CursorPaginator(self.mock_client, "items")
        response_data = {}
        results = [{"id": 1}]
        self.assertTrue(paginator.is_last_page(response_data, results))

    def test_is_last_page_empty_results(self):
        """Tests is_last_page when results are empty."""
        paginator = CursorPaginator(self.mock_client, "items")
        response_data = {"next_cursor": "abc"}
        results = []
        self.assertTrue(paginator.is_last_page(response_data, results))

    def test_is_last_page_has_more_data(self):
        """Tests is_last_page when there's more data."""
        paginator = CursorPaginator(self.mock_client, "items")
        response_data = {"next_cursor": "abc"}
        results = [{"id": 1}]
        self.assertFalse(paginator.is_last_page(response_data, results))

    def test_fetch_all_single_page(self):
        """Tests fetching data when there is only one page."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "results": [{"id": 1}, {"id": 2}],
            "next_cursor": None,
        }
        self.mock_client.get.return_value = mock_response

        paginator = CursorPaginator(self.mock_client, "items")
        all_items = list(paginator.fetch_all())

        self.assertEqual(len(all_items), 1)
        self.assertEqual(all_items[0], [{"id": 1}, {"id": 2}])
        self.mock_client.get.assert_called_once()

    def test_fetch_all_multiple_pages_cursor_in_params(self):
        """Tests fetching data from multiple pages with cursor in params."""
        mock_response_1 = MagicMock()
        mock_response_1.json.return_value = {
            "results": [{"id": 1}, {"id": 2}],
            "next_cursor": "cursor123",
        }

        mock_response_2 = MagicMock()
        mock_response_2.json.return_value = {
            "results": [{"id": 3}],
            "next_cursor": None,
        }

        self.mock_client.get.side_effect = [mock_response_1, mock_response_2]

        paginator = CursorPaginator(
            self.mock_client, "items", cursor_param="cursor", cursor_location="param"
        )
        pages = list(paginator.fetch_all())

        # Flatten the list of lists into a single list of results
        all_results = [item for page in pages for item in page]

        self.assertEqual(len(pages), 2)
        self.assertEqual(self.mock_client.get.call_count, 2)
        self.assertEqual(all_results, [{"id": 1}, {"id": 2}, {"id": 3}])

    def test_fetch_all_multiple_pages_cursor_in_headers(self):
        """Tests fetching data from multiple pages with cursor in headers."""
        mock_response_1 = MagicMock()
        mock_response_1.json.return_value = {
            "results": [{"id": 1}],
            "paging": {"next_search_after": "cursor123"},
        }

        mock_response_2 = MagicMock()
        mock_response_2.json.return_value = {
            "results": [{"id": 2}],
            "paging": {"next_search_after": None},
        }

        self.mock_client.get.side_effect = [mock_response_1, mock_response_2]

        paginator = CursorPaginator(
            self.mock_client,
            "items",
            cursor_param="Search-After",
            cursor_location="header",
            cursor_response_path="paging.next_search_after",
        )
        pages = list(paginator.fetch_all())

        # Flatten the list of lists into a single list of results
        all_results = [item for page in pages for item in page]

        self.assertEqual(len(pages), 2)
        self.assertEqual(self.mock_client.get.call_count, 2)
        self.assertEqual(all_results, [{"id": 1}, {"id": 2}])

        # Verify headers were passed correctly
        calls = self.mock_client.get.call_args_list
        self.assertIn("headers", calls[1][1])
        self.assertEqual(calls[1][1]["headers"]["Search-After"], "cursor123")

    def test_fetch_all_with_pit_pagination(self):
        """Tests Point-In-Time pagination (Greenhouse Audit Log pattern)."""
        mock_response_1 = MagicMock()
        mock_response_1.json.return_value = {
            "results": [{"id": 1}],
            "paging": {"next_search_after": "cursor123", "pit_id": "pit456"},
        }

        mock_response_2 = MagicMock()
        mock_response_2.json.return_value = {
            "results": [{"id": 2}],
            "paging": {"next_search_after": None, "pit_id": "pit456"},
        }

        self.mock_client.get.side_effect = [mock_response_1, mock_response_2]

        paginator = CursorPaginator(
            self.mock_client,
            "events",
            cursor_param="Search-After",
            cursor_location="header",
            cursor_response_path="paging.next_search_after",
            context_param="Pit-Id",
            context_location="header",
            context_response_path="paging.pit_id",
            page_size_param="Size",
            page_size_location="header",
            page_size=500,
        )
        pages = list(paginator.fetch_all())

        # Flatten the list of lists into a single list of results
        all_results = [item for page in pages for item in page]

        self.assertEqual(len(pages), 2)
        self.assertEqual(self.mock_client.get.call_count, 2)
        self.assertEqual(all_results, [{"id": 1}, {"id": 2}])

        # Verify both cursor and context (pit_id) were passed
        calls = self.mock_client.get.call_args_list
        second_call_headers = calls[1][1]["headers"]
        self.assertEqual(second_call_headers["Search-After"], "cursor123")
        self.assertEqual(second_call_headers["Pit-Id"], "pit456")
        self.assertEqual(second_call_headers["Size"], "500")

    def test_fetch_all_with_page_size_in_params(self):
        """Tests pagination with page size in query parameters."""
        mock_response = MagicMock()
        mock_response.json.return_value = {"results": [{"id": 1}], "next_cursor": None}
        self.mock_client.get.return_value = mock_response

        paginator = CursorPaginator(
            self.mock_client,
            "items",
            page_size_param="limit",
            page_size_location="param",
            page_size=100,
        )
        list(paginator.fetch_all())

        # Verify page size was passed in params
        calls = self.mock_client.get.call_args_list
        self.assertEqual(calls[0][1]["params"]["limit"], 100)

    def test_fetch_all_empty_response(self):
        """Tests fetching when the first page is empty."""
        mock_response = MagicMock()
        mock_response.json.return_value = {"results": []}
        self.mock_client.get.return_value = mock_response

        paginator = CursorPaginator(self.mock_client, "items")
        all_items = list(paginator.fetch_all())

        self.assertEqual(len(all_items), 0)
        self.mock_client.get.assert_called_once()

    def test_fetch_all_handles_api_error(self):
        """Tests if the paginator stops and raises an exception on API error."""
        # Simulate an API error response
        mock_response = MagicMock()
        mock_response.raise_for_status.side_effect = requests.exceptions.HTTPError(
            "404 Client Error: Not Found"
        )
        self.mock_client.get.return_value = mock_response

        paginator = CursorPaginator(self.mock_client, "items")

        # Use a context manager to verify the exception is raised
        with self.assertRaises(requests.exceptions.HTTPError):
            list(paginator.fetch_all())  # Try to consume the generator

        # Ensure it tried only once and stopped
        self.mock_client.get.assert_called_once()

    def test_fetch_all_handles_api_error_on_second_page(self):
        """Tests if the paginator propagates errors that occur on subsequent pages."""
        # First page succeeds
        mock_response_1 = MagicMock()
        mock_response_1.json.return_value = {
            "results": [{"id": 1}],
            "next_cursor": "cursor123",
        }

        # Second page fails
        mock_response_2 = MagicMock()
        mock_response_2.raise_for_status.side_effect = requests.exceptions.HTTPError(
            "500 Server Error: Internal Server Error"
        )

        self.mock_client.get.side_effect = [mock_response_1, mock_response_2]

        paginator = CursorPaginator(self.mock_client, "items")

        # The first page should be yielded, then an error on the second
        with self.assertRaises(requests.exceptions.HTTPError):
            list(paginator.fetch_all())

        # Ensure it tried twice (first succeeded, second failed)
        self.assertEqual(self.mock_client.get.call_count, 2)
