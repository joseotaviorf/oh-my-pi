"""
Maps Unity Catalog / Spark SQL types to AWS Glue (Hive-compatible) types
and vice versa.

Ported from the UC-Glue bi-directional sync script.  These are pure
functions with no external dependencies.
"""

from __future__ import annotations

import re
from typing import Dict, List

_UC_TO_GLUE_SIMPLE: Dict[str, str] = {
    "BOOLEAN": "boolean",
    "BYTE": "tinyint",
    "TINYINT": "tinyint",
    "SHORT": "smallint",
    "SMALLINT": "smallint",
    "INT": "int",
    "INTEGER": "int",
    "LONG": "bigint",
    "BIGINT": "bigint",
    "FLOAT": "float",
    "DOUBLE": "double",
    "DATE": "date",
    "TIMESTAMP": "timestamp",
    "TIMESTAMP_NTZ": "timestamp",
    "STRING": "string",
    "BINARY": "binary",
    "NULL": "void",
    "VOID": "void",
    "INTERVAL": "string",
}

_GLUE_TO_UC_SIMPLE: Dict[str, str] = {
    "boolean": "BOOLEAN",
    "tinyint": "TINYINT",
    "smallint": "SMALLINT",
    "int": "INT",
    "integer": "INT",
    "bigint": "BIGINT",
    "float": "FLOAT",
    "double": "DOUBLE",
    "date": "DATE",
    "timestamp": "TIMESTAMP",
    "string": "STRING",
    "binary": "BINARY",
    "void": "VOID",
}

_DECIMAL_RE = re.compile(r"^DECIMAL\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)$", re.IGNORECASE)
_ARRAY_RE = re.compile(r"^ARRAY\s*<(.+)>$", re.IGNORECASE)
_MAP_RE = re.compile(r"^MAP\s*<(.+)>$", re.IGNORECASE)
_STRUCT_RE = re.compile(r"^STRUCT\s*<(.+)>$", re.IGNORECASE)


def _split_top_level(s: str, max_splits: int = -1) -> List[str]:
    """Split by comma respecting nested angle brackets and parentheses.

    Parentheses count towards depth so that the comma inside a parameterised
    type such as ``decimal(10,7)`` is not mistaken for a field separator.
    """
    parts: List[str] = []
    depth = 0
    buf: List[str] = []
    splits = 0
    for ch in s:
        if ch in "<(":
            depth += 1
            buf.append(ch)
        elif ch in ">)":
            depth -= 1
            buf.append(ch)
        elif ch == "," and depth == 0:
            if 0 < max_splits <= splits:
                buf.append(ch)
            else:
                parts.append("".join(buf).strip())
                buf = []
                splits += 1
        else:
            buf.append(ch)
    if buf:
        parts.append("".join(buf).strip())
    return parts


def map_uc_type_to_glue(uc_type: str) -> str:
    """Map a Unity Catalog / Spark SQL column type to a Glue/Hive type."""
    trimmed = uc_type.strip()
    upper = trimmed.upper()

    if upper in _UC_TO_GLUE_SIMPLE:
        return _UC_TO_GLUE_SIMPLE[upper]

    m = _DECIMAL_RE.match(trimmed)
    if m:
        return f"decimal({m.group(1)},{m.group(2)})"

    m = _ARRAY_RE.match(trimmed)
    if m:
        return f"array<{map_uc_type_to_glue(m.group(1))}>"

    m = _MAP_RE.match(trimmed)
    if m:
        kv = _split_top_level(m.group(1), max_splits=1)
        if len(kv) == 2:
            return f"map<{map_uc_type_to_glue(kv[0])},{map_uc_type_to_glue(kv[1])}>"
        return "string"

    m = _STRUCT_RE.match(trimmed)
    if m:
        fields = _split_top_level(m.group(1))
        mapped = []
        for f in fields:
            parts = f.split(":", 1)
            if len(parts) == 2:
                mapped.append(f"{parts[0].strip()}:{map_uc_type_to_glue(parts[1])}")
            else:
                mapped.append(f.strip())
        return "struct<{}>".format(",".join(mapped))

    return "string"


def coerce_glue_type_for_json(glue_type: str) -> str:
    """Coerce Glue types that break OpenX JsonSerDe reads to ``string``.

    Only ``timestamp`` and ``date`` are fragile: OpenX parses them with
    ``Timestamp.valueOf`` / ``Date.valueOf``, which reject the ISO-8601 ``T``
    separator and ``Z`` suffix emitted by our JSON producers, and OpenX has no
    ``timestamp.formats`` property to configure around it. Registering them as
    ``string`` keeps the read working; the consumer casts the value back to the
    real type before writing to its target table.

    Everything else is left alone. ``decimal`` and ``array`` / ``struct`` /
    ``map`` were also coerced while the catalog was on HCatalog JsonSerDe
    (#27238) because that SerDe raised ``String → HiveDecimal`` and
    ``ArrayList → HCatRecord`` ClassCasts; OpenX handles all of them natively,
    so coercing them would lose the nested payload for no benefit.

    ``binary`` is intentionally left unchanged (deferred separately).
    Partition keys must not be passed through this helper.
    """
    trimmed = (glue_type or "").strip()
    lower = trimmed.lower()
    if not lower:
        return "string"
    if lower in ("timestamp", "date"):
        return "string"
    return trimmed


def map_uc_type_to_glue_for_json(uc_type: str) -> str:
    """Map UC/Spark type to Glue for JSON tables (fragile types → ``string``)."""
    return coerce_glue_type_for_json(map_uc_type_to_glue(uc_type))


def map_glue_type_to_uc(glue_type: str) -> str:
    """Map a Glue/Hive column type to a Unity Catalog / Spark SQL type."""
    trimmed = glue_type.strip()
    lower = trimmed.lower()

    if lower in _GLUE_TO_UC_SIMPLE:
        return _GLUE_TO_UC_SIMPLE[lower]

    m = _DECIMAL_RE.match(trimmed)
    if m:
        return f"DECIMAL({m.group(1)},{m.group(2)})"

    m = _ARRAY_RE.match(trimmed)
    if m:
        return f"ARRAY<{map_glue_type_to_uc(m.group(1))}>"

    m = _MAP_RE.match(trimmed)
    if m:
        kv = _split_top_level(m.group(1), max_splits=1)
        if len(kv) == 2:
            return f"MAP<{map_glue_type_to_uc(kv[0])},{map_glue_type_to_uc(kv[1])}>"
        return "STRING"

    m = _STRUCT_RE.match(trimmed)
    if m:
        fields = _split_top_level(m.group(1))
        mapped = []
        for f in fields:
            parts = f.split(":", 1)
            if len(parts) == 2:
                mapped.append(f"{parts[0].strip()}:{map_glue_type_to_uc(parts[1])}")
            else:
                mapped.append(f.strip())
        return "STRUCT<{}>".format(",".join(mapped))

    return "STRING"
