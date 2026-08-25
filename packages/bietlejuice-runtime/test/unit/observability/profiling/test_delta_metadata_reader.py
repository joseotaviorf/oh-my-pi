from datetime import datetime, timezone
from unittest import mock

from bietlejuice.observability.profiling.delta_metadata_reader import (
    DeltaMetadataReader,
    _latest_partition_spec_with_data,
    _max_column_from_stats,
    _parse_num_records,
    _sum_num_records,
    partition_key_from_logical_date,
    partition_key_to_predicate,
    partition_key_to_spec,
)


class TestPartitionKeyFromLogicalDate:
    def test_builds_standard_year_month_day_key(self):
        key = partition_key_from_logical_date("2026-07-23", ["year", "month", "day"])
        assert key == [
            {"name": "year", "value": "2026"},
            {"name": "month", "value": "07"},
            {"name": "day", "value": "23"},
        ]

    def test_returns_none_for_non_standard_partitions(self):
        assert partition_key_from_logical_date("2026-07-23", ["dt"]) is None

    def test_returns_none_for_invalid_date(self):
        assert (
            partition_key_from_logical_date("bad-date", ["year", "month", "day"])
            is None
        )


class TestPartitionKeyHelpers:
    def test_partition_key_to_spec_and_predicate(self):
        key = [
            {"name": "year", "value": "2026"},
            {"name": "month", "value": "07"},
            {"name": "day", "value": "23"},
        ]
        assert partition_key_to_spec(key) == "year=2026/month=07/day=23"
        assert partition_key_to_predicate(key) == (
            "`year` = '2026' AND `month` = '07' AND `day` = '23'"
        )


class TestSumNumRecords:
    def test_sums_all_active_files_for_table_grain(self):
        files = [
            ({"year": "2026", "month": "07", "day": "22"}, 100),
            ({"year": "2026", "month": "07", "day": "23"}, 42),
        ]
        assert _sum_num_records(files) == (142, True)

    def test_filters_partition_with_padding_tolerance(self):
        files = [
            ({"year": "2026", "month": "7", "day": "23"}, 10),
            ({"year": "2026", "month": "07", "day": "23"}, 5),
            ({"year": "2026", "month": "07", "day": "22"}, 99),
        ]
        target = {"year": "2026", "month": "07", "day": "23"}
        assert _sum_num_records(files, target=target) == (15, True)

    def test_empty_partition_is_zero_with_complete_stats(self):
        files = [
            ({"year": "2026", "month": "07", "day": "22"}, 99),
        ]
        target = {"year": "2026", "month": "07", "day": "23"}
        assert _sum_num_records(files, target=target) == (0, True)

    def test_missing_stats_marks_incomplete(self):
        files = [({"year": "2026", "month": "07", "day": "23"}, None)]
        assert _sum_num_records(files) == (None, False)


class TestParseNumRecords:
    def test_parses_json_stats_string_and_missing(self):
        assert _parse_num_records('{"numRecords": 42}') == 42
        assert _parse_num_records(None) is None


class TestLatestPartitionSpecWithData:
    def test_picks_chronologically_latest_partition_with_rows(self):
        files = [
            ({"year": "2026", "month": "07", "day": "23"}, 0),
            ({"year": "2026", "month": "07", "day": "22"}, 10),
            ({"year": "2026", "month": "07", "day": "21"}, 99),
            ({"year": "2026", "month": "7", "day": "20"}, 5),
        ]
        assert (
            _latest_partition_spec_with_data(files, ["year", "month", "day"])
            == "year=2026/month=07/day=22"
        )

    def test_returns_none_when_all_partitions_empty(self):
        files = [
            ({"year": "2026", "month": "07", "day": "23"}, 0),
            ({"year": "2026", "month": "07", "day": "22"}, 0),
        ]
        assert _latest_partition_spec_with_data(files, ["year", "month", "day"]) is None

    def test_incomplete_stats_still_count_when_known_positive(self):
        files = [
            ({"year": "2026", "month": "07", "day": "23"}, None),
            ({"year": "2026", "month": "07", "day": "22"}, 5),
            ({"year": "2026", "month": "07", "day": "22"}, None),
        ]
        assert (
            _latest_partition_spec_with_data(files, ["year", "month", "day"])
            == "year=2026/month=07/day=22"
        )


class TestActiveFilesCache:
    def test_active_files_collected_once_per_fqtn(self):
        reader = DeltaMetadataReader(mock.MagicMock())
        files = [({"year": "2026"}, 10)]
        reader._all_files_dataframe = mock.MagicMock(return_value=_fake_files_df(files))
        assert reader.row_count_from_log("db.t") == (10, True)
        assert (
            reader.latest_partition_with_data_from_log("db.t", ["year", "month", "day"])
            is None
        )
        assert reader.partition_row_count_from_log(
            "db.t",
            [{"name": "year", "value": "2026"}],
        ) == (10, True)
        reader._all_files_dataframe.assert_called_once_with("db.t")


def _fake_files_df(files: list[tuple[dict[str, str], int | None]]):
    """Minimal DataFrame stub: select().collect() returns partitionValues/stats rows."""
    rows = []
    for partition_values, num_records in files:
        stats = None if num_records is None else {"numRecords": num_records}
        rows.append({"partitionValues": partition_values, "stats": stats})
    df = mock.MagicMock()
    df.select.return_value.collect.return_value = rows
    return df


class TestMaxColumnFromStats:
    def test_returns_max_from_complete_stats(self):
        stats = [
            {"maxValues": {"ts_load": "2026-08-01T10:00:00Z"}},
            {"maxValues": {"ts_load": "2026-08-03T08:00:00Z"}},
        ]
        latest, complete = _max_column_from_stats(stats, "ts_load")
        assert complete is True
        assert latest == datetime(2026, 8, 3, 8, 0, tzinfo=timezone.utc)

    def test_incomplete_stats_when_missing_column(self):
        stats = [{"maxValues": {"other": "2026-08-01"}}]
        latest, complete = _max_column_from_stats(stats, "ts_load")
        assert latest is None
        assert complete is False

    def test_empty_table_returns_none_complete(self):
        latest, complete = _max_column_from_stats([], "ts_load")
        assert latest is None
        assert complete is True


class TestLatestPartitionWithDataFromLog:
    def test_returns_none_for_non_standard_partitions(self):
        reader = DeltaMetadataReader(mock.MagicMock())
        reader._active_files = mock.MagicMock()
        assert reader.latest_partition_with_data_from_log("db.t", ["dt"]) is None
        reader._active_files.assert_not_called()
