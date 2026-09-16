"""
Allowed metastore input layers by DAG output layer (workflow.layer).

Aligned with cross-layer rules: no domain-specific overrides.
Unknown output layers return None (caller should skip validation).
"""

from typing import Dict, FrozenSet, Optional

# Output layer (declaration workflow.layer, lowercased) -> allowed source layers
ALLOWED_SOURCE_LAYERS_BY_OUTPUT: Dict[str, FrozenSet[str]] = {
    # Ingestion / mirror — typically no lake SQL in-repo; extractor often empty
    "raw": frozenset({"raw"}),
    "clean": frozenset({"raw", "clean"}),
    "enrich": frozenset({"transactional", "clean", "enrich", "core"}),
    # Three-layer taxonomy. Mirrors enrich's allow-list — it is the same kind of
    # output — plus transformation itself for chained transformations. Without
    # this key allowed_layers_for_output() returns None and the caller skips the
    # DAG entirely, so a transformation DAG would pass CI unchecked.
    "transformation": frozenset(
        {"transactional", "clean", "enrich", "core", "transformation"}
    ),
    "dw": frozenset({"clean", "enrich", "core", "dw"}),
    "metric": frozenset({"enrich", "core", "dw", "metric"}),
    # Dimensions/measures may read clean+ layers; metrics also read qube_dimensions/measures.
    "qube": frozenset({"clean", "enrich", "dw", "metric", "core", "qube"}),
    "core": frozenset({"transactional", "clean", "core"}),
    "reverse": frozenset({"clean", "enrich", "dw", "metric"}),
    # Consumption = final materialized output (Luigi-style scheduled query
    # materializations into governed schemas). Not a transformation layer itself —
    # it aggregates already-treated data from the transformation layers (clean,
    # enrich) plus already-consolidated modeling layers (dw, metric, qube). May
    # also read other consumption tables (chained materializations).
    # core is intentionally excluded (master data is not a consumption input
    # unless product explicitly opts in later).
    #
    # Migration note: registered consumption schemas share physical names with
    # legacy enrich writers (ops_* / forrent_postcontract). Schema-name policy
    # classifies those FQNs as consumption, so enrich's allow-list below must NOT
    # gain "consumption" as a temporary escape hatch — flip declarations to
    # layer: consumption instead (bulk enrich_luigijr_* migration).
    "consumption": frozenset(
        {"clean", "enrich", "dw", "metric", "qube", "consumption", "transformation"}
    ),
}


def allowed_layers_for_output(output_layer: str) -> Optional[FrozenSet[str]]:
    """
    Return allowed lowercase layer ids for tables referenced by this DAG,
    or None if output_layer is not in the policy matrix.
    """
    if not output_layer:
        return None
    return ALLOWED_SOURCE_LAYERS_BY_OUTPUT.get(output_layer.strip().lower())
