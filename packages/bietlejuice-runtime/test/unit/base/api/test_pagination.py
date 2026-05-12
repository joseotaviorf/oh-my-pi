import unittest
from unittest.mock import MagicMock

import requests

from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.common.exceptions import APIException
from bietlejuice.base.api.pagination.header_link import HeaderLinkPaginator


class TestHeaderLinkPaginator(unittest.TestCase):
    def setUp(self):
        """Sets up the test environment before each test."""
        self.mock_client = MagicMock(spec=BaseAPIClient)
        self.mock_client.base_url = "http://fakeapi.com"
        self.mock_client.session = MagicMock()
        self.mock_client.timeout = 30
        self.mock_client._handle_response.side_effect = self.mock_handle_response

    def mock_handle_response(self, response):
        """Mock function to simulate the client's _handle_response."""
        if not response.ok:
            raise APIException("API Error")

    def test_initialization(self):
        """Tests if the paginator is initialized correctly."""
        endpoint = "items"
        params = {"limit": 10}
        paginator = HeaderLinkPaginator(self.mock_client, endpoint, params)

        self.assertEqual(paginator.client, self.mock_client)
        self.assertEqual(paginator.next_url, "http://fakeapi.com/items")
        self.assertEqual(paginator.params, params)

    def test_parse_link_header_with_next_link(self):
        """Tests parsing a 'Link' header that contains a 'next' link."""
        paginator = HeaderLinkPaginator(self.mock_client, "items")
        headers = {
            "Link": '<http://fakeapi.com/items?page=2>; rel="next", <http://fakeapi.com/items?page=1>; rel="first"'
        }
        next_url = paginator._parse_link_header(headers)
        self.assertEqual(next_url, "http://fakeapi.com/items?page=2")

    def test_parse_link_header_without_next_link(self):
        """Tests parsing a 'Link' header without a 'next' link."""
        paginator = HeaderLinkPaginator(self.mock_client, "items")
        headers = {"Link": '<http://fakeapi.com/items?page=1>; rel="first"'}
        next_url = paginator._parse_link_header(headers)
        self.assertIsNone(next_url)

    def test_parse_link_header_with_no_link_header(self):
        """Tests the behavior when there is no 'Link' header."""
        paginator = HeaderLinkPaginator(self.mock_client, "items")
        headers = {}
        next_url = paginator._parse_link_header(headers)
        self.assertIsNone(next_url)

    def test_fetch_all_multiple_pages(self):
        """Tests fetching data from multiple pages."""
        mock_response_1 = MagicMock()
        mock_response_1.ok = True
        mock_response_1.json.return_value = [{"id": 1}, {"id": 2}]
        mock_response_1.headers = {
            "Link": '<http://fakeapi.com/items?page=2>; rel="next"'
        }

        mock_response_2 = MagicMock()
        mock_response_2.ok = True
        mock_response_2.json.return_value = [{"id": 3}]
        mock_response_2.headers = {}

        self.mock_client.session.get.side_effect = [mock_response_1, mock_response_2]

        paginator = HeaderLinkPaginator(self.mock_client, "items")
        all_items = list(paginator.fetch_all())

        self.assertEqual(len(all_items), 2)
        self.assertEqual(all_items[0], [{"id": 1}, {"id": 2}])
        self.assertEqual(all_items[1], [{"id": 3}])

        self.assertEqual(self.mock_client.session.get.call_count, 2)
        self.mock_client.session.get.assert_any_call(
            "http://fakeapi.com/items", params={}, timeout=30
        )
        self.mock_client.session.get.assert_any_call(
            "http://fakeapi.com/items?page=2", params={}, timeout=30
        )

    def test_fetch_all_single_page(self):
        """Tests fetching data when there is only one page."""
        mock_response = MagicMock()
        mock_response.ok = True
        mock_response.json.return_value = [{"id": 1}]
        mock_response.headers = {}
        self.mock_client.session.get.return_value = mock_response

        paginator = HeaderLinkPaginator(self.mock_client, "items")
        all_items = list(paginator.fetch_all())

        self.assertEqual(len(all_items), 1)
        self.assertEqual(all_items[0], [{"id": 1}])
        self.mock_client.session.get.assert_called_once()

    def test_fetch_all_handles_api_error(self):
        """Tests if an exception is raised when the API returns an error."""
        mock_response = MagicMock()
        mock_response.ok = False  # Simulates an error response (e.g., status 500)
        self.mock_client.session.get.return_value = mock_response

        paginator = HeaderLinkPaginator(self.mock_client, "items")

        with self.assertRaises(APIException):
            list(paginator.fetch_all())

    def test_fetch_all_handles_malformed_json(self):
        """Tests what happens if the response is not valid JSON."""
        mock_response = MagicMock()
        mock_response.ok = True
        mock_response.json.side_effect = requests.exceptions.JSONDecodeError(
            "Expecting value", "doc", 0
        )
        self.mock_client.session.get.return_value = mock_response

        paginator = HeaderLinkPaginator(self.mock_client, "items")

        with self.assertRaises(requests.exceptions.JSONDecodeError):
            list(paginator.fetch_all())
