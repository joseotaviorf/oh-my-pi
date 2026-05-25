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
    "dw": frozenset({"clean", "enrich", "core", "dw"}),
    "metric": frozenset({"enrich", "core", "dw", "metric"}),
    "qube": frozenset({"enrich", "dw", "metric", "qube"}),
    "core": frozenset({"transactional", "clean", "core"}),
    "reverse": frozenset({"clean", "enrich", "dw", "metric"}),
}


def allowed_layers_for_output(output_layer: str) -> Optional[FrozenSet[str]]:
    """
    Return allowed lowercase layer ids for tables referenced by this DAG,
    or None if output_layer is not in the policy matrix.
    """
    if not output_layer:
        return None
    return ALLOWED_SOURCE_LAYERS_BY_OUTPUT.get(output_layer.strip().lower())
