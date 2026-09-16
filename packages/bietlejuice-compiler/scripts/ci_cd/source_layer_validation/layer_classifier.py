"""
Map metastore schema names to logical data layers.

Used by all source-layer policy profiles (core Spark jobs today; DW/metric later).
"""

import re
from typing import Iterable, Optional, Tuple

from bietlejuice.base.db.datalake_metastore_mapping import CONSUMPTION_SCHEMAS

# Fully-qualified table: schema.table (Hive/Spark metastore style)
TABLE_FQN_PATTERN = re.compile(r"^[a-zA-Z][a-zA-Z0-9_]*\.[a-zA-Z][a-zA-Z0-9_]*$")


def parse_table_fqn(value: object) -> Optional[Tuple[str, str]]:
    """
    Return (schema, table) if value looks like schema.table, else None.
    """
    if not isinstance(value, str):
        return None
    value = value.strip().strip('"').strip("'")
    if not TABLE_FQN_PATTERN.match(value):
        return None
    schema, table = value.split(".", 1)
    return schema, table


def classify_schema_to_layer(schema: str) -> str:
    """
    Infer layer from schema name (first segment of schema.table).

    Aligns with bi-etl-ejuice metastore naming (see naming_conventions).

    Returns lowercase layer id: raw, clean, transactional, enrich, dw, metric, core,
    qube, reverse, consumption, transformation, unknown.
    """
    if not schema:
        return "unknown"
    s = schema.lower()

    # Registered consumption domains (prefix-free). Checked before prefix rules so
    # physical names like ops_finance classify as consumption — even though legacy
    # enrich writers historically used the same physical name via the datalake_
    # drop-prefix exception. See CONSUMPTION_SCHEMAS docstring (migration gate).
    if s in CONSUMPTION_SCHEMAS:
        return "consumption"
    if s.startswith("reverse_"):
        return "reverse"
    if s.startswith("qube_"):
        return "qube"
    if s.startswith("metric_"):
        return "metric"
    if s.startswith("transformation_"):
        return "transformation"
    if s.startswith("dw_"):
        return "dw"
    if s.startswith("core_"):
        return "core"
    if s.startswith("datalake_"):
        if s.endswith("_raw"):
            return "raw"
        if s.endswith("_clean"):
            return "clean"
        # Naming convention: datalake_<context>_transactional (after raw/clean checks).
        if s.endswith("_transactional"):
            return "transactional"
        return "enrich"

    return "unknown"


def classify_table_fqn(table_fqn: str) -> Optional[Tuple[str, str, str]]:
    """
    Classify a schema.table string.

    Returns (full_fqn, layer, schema) or None if not a valid FQN.
    """
    parsed = parse_table_fqn(table_fqn)
    if not parsed:
        return None
    schema, _ = parsed
    layer = classify_schema_to_layer(schema)
    return table_fqn.strip().strip('"').strip("'"), layer, schema


def is_layer_allowed(layer: str, allowed_layers: Iterable[str]) -> bool:
    """allowed_layers: list of layer ids (case-insensitive)."""
    allowed = {x.lower() for x in allowed_layers}
    return layer.lower() in allowed
