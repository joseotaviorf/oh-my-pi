from __future__ import annotations

import json
from typing import Optional

EMPTY_VALUES = {"", "null", "none", "[]"}


def parse_requested_tables(raw_value: Optional[str]) -> list[str]:
    """
    Normalize the `tables` trigger conf, forwarded as a Spark job argument, into a
    list of table names.

    The argument is rendered by Jinja as `... | tojson`, so a trigger form list
    arrives as `["a", "b"]` and an omitted conf arrives as `null`. A
    comma-separated string is also accepted, since it is easier to type by hand.

    :param raw_value: The raw Spark job argument.
    :return: The requested table names, or an empty list meaning "every table".
    """

    if raw_value is None:
        return []

    value = raw_value.strip()
    if value.lower() in EMPTY_VALUES:
        return []

    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        decoded = value

    if decoded is None:
        return []

    if isinstance(decoded, str):
        items: list = decoded.split(",")
    elif isinstance(decoded, (list, tuple)):
        items = list(decoded)
    else:
        items = [decoded]

    return [str(item).strip() for item in items if str(item).strip()]


def is_table_selected(table_name: str, raw_value: Optional[str]) -> bool:
    """
    Tell whether `table_name` should be exported in this run.

    An empty selection means every table configured in `tables_customization` is
    exported, which is what scheduled runs do.

    :param table_name: The table the current Spark job instance is exporting.
    :param raw_value: The raw `tables` Spark job argument.
    :return: True when the table must be exported.
    """

    requested_tables = parse_requested_tables(raw_value)
    if not requested_tables:
        return True

    return table_name.strip().lower() in {
        requested.lower() for requested in requested_tables
    }
