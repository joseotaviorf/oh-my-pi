"""Unit tests for the Salesforce ID-fetch time windows (daily vs hourly)."""

from unittest import mock

from bietlejuice.base.sst.domains.salesforce.api import calls

PARTITION_DATE = "2026-06-02"
ENDPOINT = "https://sf.example/services/data/v58.0/sobjects/Case"


class TestGetUpdatedDeletedLst:
    def _run(self, mock_get_change_lst, **kwargs):
        mock_get_change_lst.side_effect = [
            {"ids": ["u1", "u2"]},
            {"deletedRecords": [{"id": "d1"}]},
        ]
        result = calls.get_updated_deleted_lst(
            endpoint=ENDPOINT,
            partition_date=PARTITION_DATE,
            access_token="token",
            **kwargs,
        )
        windows = [
            (call.kwargs["start_ts"], call.kwargs["end_ts"])
            for call in mock_get_change_lst.call_args_list
        ]
        return result, windows

    @mock.patch.object(calls, "get_change_lst")
    def test_daily_window_when_no_hour(self, mock_get_change_lst):
        result, windows = self._run(mock_get_change_lst)

        assert sorted(result) == ["d1", "u1", "u2"]
        assert windows == [
            ("2026-06-02T00:00:00Z", "2026-06-03T00:00:00Z"),
            ("2026-06-02T00:00:00Z", "2026-06-03T00:00:00Z"),
        ]

    @mock.patch.object(calls, "get_change_lst")
    def test_hourly_window_stops_before_next_hour(self, mock_get_change_lst):
        # /updated and /deleted treat ``end`` inclusively -> HH:59:59.
        _, windows = self._run(mock_get_change_lst, partition_hour="05")

        assert windows == [
            ("2026-06-02T05:00:00Z", "2026-06-02T05:59:59Z"),
            ("2026-06-02T05:00:00Z", "2026-06-02T05:59:59Z"),
        ]

    @mock.patch.object(calls, "get_change_lst")
    def test_hour_zero_is_a_real_hour(self, mock_get_change_lst):
        _, windows = self._run(mock_get_change_lst, partition_hour="00")

        assert windows[0] == ("2026-06-02T00:00:00Z", "2026-06-02T00:59:59Z")


class TestGetUpdatedLstSystemMod:
    def _run(self, mock_query_all, **kwargs):
        mock_query_all.return_value = ([{"Id": "a"}, {"Id": "a"}, {"Id": "b"}], None)
        result = calls.get_updated_lst_system_mod(
            endpoint=ENDPOINT,
            partition_date=PARTITION_DATE,
            api_entity="Case",
            access_token="token",
            **kwargs,
        )
        soql = mock_query_all.call_args.kwargs["query"]
        return result, soql

    @mock.patch.object(calls, "query_all")
    def test_daily_window_when_no_hour(self, mock_query_all):
        result, soql = self._run(mock_query_all)

        assert sorted(result) == ["a", "b"]
        assert "SystemModstamp >= 2026-06-02T00:00:00Z" in soql
        assert "SystemModstamp < 2026-06-03T00:00:00Z" in soql

    @mock.patch.object(calls, "query_all")
    def test_hourly_window_uses_full_hour(self, mock_query_all):
        # SOQL end bound is exclusive (<), so the window covers the full hour.
        _, soql = self._run(mock_query_all, partition_hour="05")

        assert "SystemModstamp >= 2026-06-02T05:00:00Z" in soql
        assert "SystemModstamp < 2026-06-02T06:00:00Z" in soql

    @mock.patch.object(calls, "query_all")
    def test_hour_zero_is_a_real_hour(self, mock_query_all):
        _, soql = self._run(mock_query_all, partition_hour="00")

        assert "SystemModstamp >= 2026-06-02T00:00:00Z" in soql
        assert "SystemModstamp < 2026-06-02T01:00:00Z" in soql
