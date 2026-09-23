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

    def test_post_sends_page_fields_in_json_body(self):
        # Arrange
        client = MagicMock()
        client.post.side_effect = [
            _resp({"data": [{"id": 1}, {"id": 2}]}),
            _resp({"data": [{"id": 3}]}),
        ]
        paginator = PagePerPagePaginator(
            client=client,
            endpoint="teams/daily-usage-data",
            per_page_param="pageSize",
            page_size=2,
            http_method="post",
            json_body={"startDate": 1789948800000, "endDate": 1790035199999},
        )

        # Act
        pages = list(paginator.fetch_all())

        # Assert
        assert pages == [[{"id": 1}, {"id": 2}], [{"id": 3}]]
        client.get.assert_not_called()
        assert client.post.call_args_list == [
            call(
                endpoint="teams/daily-usage-data",
                params={},
                json={
                    "startDate": 1789948800000,
                    "endDate": 1790035199999,
                    "page": 1,
                    "pageSize": 2,
                },
                headers=None,
            ),
            call(
                endpoint="teams/daily-usage-data",
                params={},
                json={
                    "startDate": 1789948800000,
                    "endDate": 1790035199999,
                    "page": 2,
                    "pageSize": 2,
                },
                headers=None,
            ),
        ]

    @pytest.mark.parametrize(
        "total_pages_path, first_page, last_page",
        [
            (
                "totalPages",
                {"items": [{"id": 1}], "totalPages": 2},
                {"items": [{"id": 2}], "totalPages": 2},
            ),
            (
                "pagination.numPages",
                {"items": [{"id": 1}], "pagination": {"numPages": 2}},
                {"items": [{"id": 2}], "pagination": {"numPages": 2}},
            ),
        ],
    )
    def test_total_pages_path_stops_on_full_last_page(
        self, total_pages_path, first_page, last_page
    ):
        # Arrange
        client = MagicMock()
        client.get.side_effect = [_resp(first_page), _resp(last_page)]
        paginator = PagePerPagePaginator(
            client=client,
            endpoint="x",
            page_size=1,
            total_pages_path=total_pages_path,
        )

        # Act
        pages = list(paginator.fetch_all())

        # Assert
        assert pages == [[{"id": 1}], [{"id": 2}]]
        assert client.get.call_count == 2

    def test_envelope_fields_are_stamped_on_each_row(self):
        # Arrange
        client = MagicMock()
        client.get.return_value = _resp(
            {
                "teamMemberSpend": [{"userId": "a"}, {"userId": "b"}],
                "subscriptionCycleStart": 1788220800000,
                "totalPages": 1,
            }
        )
        paginator = PagePerPagePaginator(
            client=client,
            endpoint="teams/spend",
            page_size=100,
            extract_results=lambda data: data["teamMemberSpend"],
            envelope_fields=["subscriptionCycleStart"],
        )

        # Act
        pages = list(paginator.fetch_all())

        # Assert
        assert pages == [
            [
                {"userId": "a", "subscriptionCycleStart": 1788220800000},
                {"userId": "b", "subscriptionCycleStart": 1788220800000},
            ]
        ]

    def test_invalid_http_method_raises(self):
        with pytest.raises(ValueError, match="http_method"):
            PagePerPagePaginator(client=MagicMock(), endpoint="x", http_method="put")
