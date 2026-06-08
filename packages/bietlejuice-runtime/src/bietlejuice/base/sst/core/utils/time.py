## Should be used to keep all functions that handle datetime, time filter and convertions

from datetime import datetime, timedelta, timezone
from typing import Union


# Default to 0:00 UTC
def date_str_to_utc_iso(date: Union[str, datetime], hour: int = 0) -> str:
    """
    Convert string of format %Y-%m%d into a UTC ISO STRING DATETIME object

    E.g:
      Input: 2026-05-29
      Output: 2026-05-29T00:00:00Z"
    """

    if isinstance(date, str):
        date = datetime.strptime(date, "%Y-%m-%d")

    return (
        date.replace(hour=hour, tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")
    )


def build_start_end_date(partition_date, days=1):
    """
    Build UTC ISO start and end timestamps for a partition date window.

    Args:
      partition_date: Date string in ``YYYY-MM-DD`` format.
      days: Window length in days (default 1).

    Returns:
      Tuple of ``(start_date, end_date)`` as UTC ISO strings at midnight.

    Example:
      Input: ``"2026-05-29"``, days=1
      Output: ``("2026-05-29T00:00:00Z", "2026-05-30T00:00:00Z")``
    """
    partition_date = datetime.strptime(partition_date, "%Y-%m-%d")
    start_date = date_str_to_utc_iso(partition_date)
    end_date = date_str_to_utc_iso(partition_date + timedelta(days=days))
    return start_date, end_date
