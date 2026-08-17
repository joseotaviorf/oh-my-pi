from datetime import date

from bietlejuice.shared.agents.sources import overlapping_calendar_month_bounds


def test_overlapping_calendar_month_bounds_snaps_mid_month_window():
    start, end = overlapping_calendar_month_bounds(date(2026, 8, 12), date(2026, 8, 20))
    assert start == date(2026, 8, 1)
    assert end == date(2026, 8, 31)


def test_overlapping_calendar_month_bounds_spans_year_end():
    start, end = overlapping_calendar_month_bounds(date(2025, 12, 20), date(2026, 1, 5))
    assert start == date(2025, 12, 1)
    assert end == date(2026, 1, 31)
