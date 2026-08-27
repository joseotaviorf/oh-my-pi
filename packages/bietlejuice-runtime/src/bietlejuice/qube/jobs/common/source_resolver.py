"""
Resolve Qube dimension/measure source and universe table references.

See ADR 0001: bietlejuice-runtime/docs/adr/0001-qube-flexible-source-layers.md
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, FrozenSet, Mapping, Optional, Tuple

from bietlejuice.qube.jobs.common.conf import Config

ALLOWED_SOURCE_LAYERS: FrozenSet[str] = frozenset(
    {"clean", "enrich", "dw", "metric", "core", "qube"}
)

_LAYER_SCHEMA_PREFIXES = (
    ("qube_metrics", "qube"),
    ("qube_measures", "qube"),
    ("qube_dimensions", "qube"),
    ("metric_", "metric"),
    ("enrich_", "enrich"),
    ("clean_", "clean"),
    ("core_", "core"),
    ("dw_", "dw"),
    ("raw_", "raw"),
)


@dataclass(frozen=True)
class ResolvedSource:
    """Fully resolved source table reference for a Qube spec."""

    table: str
    entity_id_col: str
    layer: str


class SourceLayerError(ValueError):
    """Raised when a source references a disallowed data layer."""


def infer_layer_from_schema(schema: str) -> Optional[str]:
    """Infer metastore layer from a schema/database name."""
    if not schema:
        return None

    normalized = schema.strip().lower()

    # QuintoAndar datalake schemas encode the layer as a SUFFIX, not a prefix
    # (e.g. datalake_ebdb_clean, datalake_ebdb_raw, datalake_ebdb_transactional).
    # A bare datalake_<context> schema is where legacy enrich writers land via the
    # datalake drop-prefix exception. Mirror the compiler's authoritative
    # classify_schema_to_layer so an omitted `layer` cannot silently fall through
    # to "core" and let a raw datalake source bypass the raw-layer rejection.
    if normalized.startswith("datalake_"):
        if normalized.endswith("_raw"):
            return "raw"
        if normalized.endswith("_clean"):
            return "clean"
        if normalized.endswith("_transactional"):
            return "transactional"
        return "enrich"

    for prefix, layer in _LAYER_SCHEMA_PREFIXES:
        if normalized == prefix or normalized.startswith(prefix):
            return layer

    if normalized in ALLOWED_SOURCE_LAYERS:
        return normalized

    return None


def _split_table_reference(table_ref: str) -> Tuple[str, str]:
    parts = table_ref.split(".")
    if len(parts) < 2 or not parts[0] or not parts[-1]:
        raise ValueError(f"Table reference must be schema.table, got '{table_ref}'")
    return parts[0], parts[-1]


def _build_table_reference(source: Mapping[str, Any], entity: str, default: str) -> str:
    schema = source.get("source_schema")
    table_name = source.get("table_name")
    if schema and table_name:
        return f"{schema}.{table_name}"

    table = source.get("table")
    if table:
        return table

    return default


def _resolve_layer(explicit_layer: Optional[str], schema: str) -> str:
    if explicit_layer:
        layer = explicit_layer.strip().lower()
    else:
        layer = infer_layer_from_schema(schema) or "core"

    if layer not in ALLOWED_SOURCE_LAYERS:
        if layer == "raw":
            raise SourceLayerError(
                "Raw layer sources are not allowed for Qube dimensions/measures. "
                "Use clean or a higher layer."
            )
        raise SourceLayerError(
            f"Layer '{layer}' is not allowed for Qube sources. "
            f"Allowed layers: {sorted(ALLOWED_SOURCE_LAYERS)}"
        )

    return layer


def qualify_table_reference(conf: Config, table_ref: str) -> str:
    """
    Qualify a schema.table reference for the active environment.

    Delegates to Config.get_table_path, which already returns fully qualified
    (dotted) references unchanged and only prefixes bare table names. Backward
    compatible with the legacy `conf.get_table_path("core", table_ref)` call.
    """
    if not table_ref:
        raise ValueError("table reference cannot be empty")
    return conf.get_table_path("core", table_ref)


def resolve_source(
    conf: Config, source: Mapping[str, Any], entity: str
) -> ResolvedSource:
    """Resolve the source table and entity id column from a spec source block."""
    entity_id_col = source.get("entity_id_col") or f"id_{entity}"

    table_ref = _build_table_reference(source, entity, f"core_{entity}.{entity}")
    schema, _ = _split_table_reference(table_ref)
    layer = _resolve_layer(source.get("layer"), schema)

    return ResolvedSource(
        table=qualify_table_reference(conf, table_ref),
        entity_id_col=entity_id_col,
        layer=layer,
    )


def resolve_universe(
    conf: Config, source: Mapping[str, Any], entity: str, entity_id_col: str
) -> Tuple[str, str]:
    """
    Resolve the closed-world universe table and its entity id column.

    Only used by dimension builds when `include_all_entities` is true. Defaults
    to `core_{entity}.{entity}` when not explicitly configured, preserving the
    original closed-world behavior.
    """
    universe_table_ref = source.get("universe_table") or f"core_{entity}.{entity}"
    universe_schema, _ = _split_table_reference(universe_table_ref)
    _resolve_layer(source.get("universe_layer"), universe_schema)

    universe_table = qualify_table_reference(conf, universe_table_ref)
    universe_entity_id_col = source.get("universe_entity_id_col") or entity_id_col

    return universe_table, universe_entity_id_col
