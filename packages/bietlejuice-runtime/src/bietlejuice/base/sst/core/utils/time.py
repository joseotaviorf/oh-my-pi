## Should be used to keep all functions that handle datetime, time filter and convertions

from datetime import datetime, timedelta, timezone
from typing import Union

from pyspark.sql import functions as F

TIMESTAMP_FORMATS = [
    "yyyy-MM-dd'T'HH:mm:ss.SSSZ",  # 2025-03-25T22:41:13.000+0000
    "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",  # 2026-06-12T18:29:31.618+00:00
    "yyyy-MM-dd'T'HH:mm:ssXXX",  # 2025-03-25T22:41:13Z
    "yyyy-MM-dd HH:mm:ss.SSS",  # 2025-03-25 22:41:13.000
    "yyyy-MM-dd HH:mm:ss",  # 2025-03-25 22:41:13
]


def standardize_timestamps(df, cols):
    for col_name in cols:
        value = F.trim(F.col(col_name).cast("string"))

        parsed_timestamp = F.coalesce(
            *[
                F.try_to_timestamp(value, F.lit(timestamp_format))
                for timestamp_format in TIMESTAMP_FORMATS
            ]
        )

        df = df.withColumn(
            col_name,
            F.date_format(parsed_timestamp, "yyyy-MM-dd HH:mm:ss"),
        )

    return df


def standard_now(is_col: bool = False):
    return (
        F.lit(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        if is_col
        else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    )


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


def build_hour_window(partition_date: str, partition_hour: str) -> tuple[str, str]:
    """Return ``(start_ts, end_ts)`` ISO-8601 UTC strings covering one hour."""
    base = datetime.strptime(partition_date, "%Y-%m-%d").replace(
        hour=int(partition_hour), tzinfo=timezone.utc
    )
    end = base + timedelta(hours=1)
    return (
        base.isoformat().replace("+00:00", "Z"),
        end.isoformat().replace("+00:00", "Z"),
    )


def build_partition_time_window(
    partition_date: str,
    partition_hour: str,
    threshold_time_hours: int,
) -> tuple[datetime, datetime, str, str, str, str]:
    """
    Build an hourly partition window ending at ``partition_date`` + ``partition_hour``.

    Returns:
        ``(window_start, window_end, partition_date_start, partition_hour_start,
        partition_date_end, partition_hour_end)``
    """
    window_end = datetime.strptime(
        f"{partition_date} {partition_hour.zfill(2)}", "%Y-%m-%d %H"
    )
    window_start = window_end - timedelta(hours=threshold_time_hours)
    return (
        window_start,
        window_end,
        window_start.strftime("%Y-%m-%d"),
        window_start.strftime("%H"),
        window_end.strftime("%Y-%m-%d"),
        window_end.strftime("%H"),
    )
