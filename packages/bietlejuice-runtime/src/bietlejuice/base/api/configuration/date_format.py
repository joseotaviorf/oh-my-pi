import calendar
from datetime import date, datetime
from typing import Optional, Union

from bietlejuice.base.api.common.client import BaseAPIClient

START_OF_DAY_SUFFIX = "T00:00:00.000Z"
END_OF_DAY_SUFFIX = "T23:59:59.999Z"
EPOCH_MILLIS_DATE_FORMAT = "epoch_millis"
MILLIS_PER_DAY = 86_400_000


def format_load_date(
    date_value: str, date_format: Optional[str], time_suffix: str
) -> Union[str, int]:
    """
    Formats a ``YYYY-MM-DD`` load date for an API request.

    Args:
        date_value: Date in ``YYYY-MM-DD``.
        date_format: ``epoch_millis`` for UTC epoch milliseconds (int), any other value
            as a strftime pattern, or None for ISO-8601 with ``time_suffix``.
        time_suffix: ``START_OF_DAY_SUFFIX`` or ``END_OF_DAY_SUFFIX``. With
            ``epoch_millis``, the end suffix resolves to the last millisecond of the day.

    Returns:
        The formatted date: int for ``epoch_millis``, str otherwise.
    """
    if date_format == EPOCH_MILLIS_DATE_FORMAT:
        day_start_millis = (
            calendar.timegm(date.fromisoformat(date_value).timetuple()) * 1000
        )
        if time_suffix == END_OF_DAY_SUFFIX:
            return day_start_millis + MILLIS_PER_DAY - 1
        return day_start_millis
    if date_format:
        return datetime.strptime(date_value, "%Y-%m-%d").strftime(date_format)
    return BaseAPIClient.format_iso_timestamp(date_value, time_suffix)
