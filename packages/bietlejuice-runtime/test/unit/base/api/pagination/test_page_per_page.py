"""Unit tests for PagePerPagePaginator."""

from unittest.mock import MagicMock, call

import pytest

from bietlejuice.base.api.pagination.page_per_page import PagePerPagePaginator


def _resp(data):
    r = MagicMock()
    r.json.return_value = data
    return r


class TestPagePerPagePaginator:
    """Test suite for PagePerPagePaginator."""

    def test_two_pages_stops_on_metadata_total_pages(self):
        client = MagicMock()
        client.get.side_effect = [
            _resp(
                {
                    "content": [{"id": 1}, {"id": 2}],
                    "metadata": {"page": 1, "totalPages": 2, "total": 3, "perPage": 2},
                }
            ),
            _resp(
                {
                    "content": [{"id": 3}],
                    "metadata": {"page": 2, "totalPages": 2, "total": 3, "perPage": 2},
                }
            ),
        ]

        paginator = PagePerPagePaginator(
            client=client,
            endpoint="requests",
            initial_params={"from": "2025-01-01"},
            page_param="page",
            per_page_param="per_page",
            page_size=2,
        )

        pages = list(paginator.fetch_all())
        assert len(pages) == 2
        assert [r["id"] for r in pages[0]] == [1, 2]
        assert [r["id"] for r in pages[1]] == [3]

        assert client.get.call_count == 2
        assert client.get.call_args_list[0] == call(
            endpoint="requests",
            params={"from": "2025-01-01", "page": 1, "per_page": 2},
            headers=None,
        )
        assert client.get.call_args_list[1] == call(
            endpoint="requests",
            params={"from": "2025-01-01", "page": 2, "per_page": 2},
            headers=None,
        )

    def test_single_page_when_len_below_page_size_without_total_pages(self):
        client = MagicMock()
        client.get.return_value = _resp({"content": [{"id": 1}]})

        paginator = PagePerPagePaginator(
            client=client,
            endpoint="x",
            initial_params={},
            page_size=10,
        )

        pages = list(paginator.fetch_all())
        assert len(pages) == 1
        assert pages[0] == [{"id": 1}]
        client.get.assert_called_once()

    def test_invalid_page_size_raises(self):
        client = MagicMock()
        with pytest.raises(ValueError, match="page_size"):
            PagePerPagePaginator(
                client=client,
                endpoint="x",
                page_size=0,
            )
