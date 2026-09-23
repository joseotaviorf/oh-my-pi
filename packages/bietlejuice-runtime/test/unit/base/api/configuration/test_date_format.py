"""Unit tests for API load-date formatting."""

import pytest

from bietlejuice.base.api.configuration.date_format import (
    END_OF_DAY_SUFFIX,
    START_OF_DAY_SUFFIX,
    format_load_date,
)


class TestFormatLoadDate:
    """Test suite for format_load_date."""

    @pytest.mark.parametrize(
        "date_format, time_suffix, expected",
        [
            ("epoch_millis", START_OF_DAY_SUFFIX, 1789948800000),
            ("epoch_millis", END_OF_DAY_SUFFIX, 1790035199999),
            ("%Y/%m/%d", END_OF_DAY_SUFFIX, "2026/09/21"),
            (None, START_OF_DAY_SUFFIX, "2026-09-21T00:00:00.000Z"),
            (None, END_OF_DAY_SUFFIX, "2026-09-21T23:59:59.999Z"),
        ],
    )
    def test_format_load_date(self, date_format, time_suffix, expected):
        assert format_load_date("2026-09-21", date_format, time_suffix) == expected

    def test_invalid_date_raises(self):
        with pytest.raises(ValueError):
            format_load_date("2026-02-30", "epoch_millis", START_OF_DAY_SUFFIX)
