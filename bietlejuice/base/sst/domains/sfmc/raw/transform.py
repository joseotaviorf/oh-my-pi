from typing import Any, Dict


def normalize_row(raw_row: Any) -> Dict[str, Any]:
    """Flatten an SFMC REST API row into a simple key-value dict.

    The SFMC Data Extension rowset endpoint returns each row wrapped as::

        {"keys": {"id_user": "123"}, "values": {"address": "Rua X", "city": "SP"}}

    This function unwraps that structure into a flat dict::

        {"address": "Rua X", "city": "SP", "id_user": "123"}

    Field names are preserved exactly as returned by the API.
    If the row is already flat (no ``values`` wrapper), it is returned unchanged.
    """
    if not isinstance(raw_row, dict):
        return {"raw_record": str(raw_row)}

    if isinstance(raw_row.get("values"), dict):
        normalized_row = dict(raw_row["values"])
        if isinstance(raw_row.get("keys"), dict):
            for key, value in raw_row["keys"].items():
                normalized_row.setdefault(key, value)
        return normalized_row

    return raw_row
