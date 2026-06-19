"""Unit tests for ``bietlejuice.base.sst.core.utils.time`` helpers."""

import pytest

from bietlejuice.base.sst.core.utils.time import is_weekend_window

# Reference dates (ISO weekday in comment): the week of 2026-06-15.
MONDAY = "2026-06-15"
FRIDAY = "2026-06-19"
SATURDAY = "2026-06-20"
SUNDAY = "2026-06-21"
NEXT_MONDAY = "2026-06-22"
TUESDAY = "2026-06-16"


class TestIsWeekendWindow:
    """Weekend window spans Friday 18:00 (inclusive) to Monday 08:00 (exclusive)."""

    @pytest.mark.parametrize(
        "partition_date, partition_hour, expected",
        [
            # Friday boundary
            (FRIDAY, "00", False),
            (FRIDAY, "17", False),
            (FRIDAY, "18", True),
            (FRIDAY, "23", True),
            # Full weekend days
            (SATURDAY, "00", True),
            (SATURDAY, "12", True),
            (SUNDAY, "23", True),
            # Monday boundary
            (NEXT_MONDAY, "00", True),
            (NEXT_MONDAY, "07", True),
            (NEXT_MONDAY, "08", False),
            (NEXT_MONDAY, "09", False),
            # Weekdays are never in the window
            (TUESDAY, "03", False),
            (MONDAY, "20", False),
        ],
    )
    def test_with_partition_hour(self, partition_date, partition_hour, expected):
        # Act / Assert
        assert is_weekend_window(partition_date, partition_hour) is expected

    @pytest.mark.parametrize(
        "partition_date, expected",
        [
            (SATURDAY, True),
            (SUNDAY, True),
            # Boundary days are partial, so without an hour they are excluded.
            (FRIDAY, False),
            (NEXT_MONDAY, False),
            (TUESDAY, False),
        ],
    )
    def test_without_partition_hour_is_conservative(self, partition_date, expected):
        # Act / Assert
        assert is_weekend_window(partition_date) is expected
        assert is_weekend_window(partition_date, None) is expected

    def test_midnight_hour_is_not_treated_as_missing(self):
        # Arrange / Act / Assert: "00" must be parsed as hour 0, not falsy.
        assert is_weekend_window(FRIDAY, "00") is False
        assert is_weekend_window(NEXT_MONDAY, "00") is True
