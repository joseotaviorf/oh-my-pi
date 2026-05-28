from typing import Any, Dict

# Prod instance topology must not leak into consolidation validation clusters;
# validation custom_configurations and preset defaults define Graviton types.
_PROD_TOPOLOGY_KEYS_FOR_CONSOLIDATION_VALIDATION = frozenset(
    {
        "node_type_id",
        "driver_node_type_id",
        "task_node_type_id",
        "instance_pool_id",
        "driver_instance_pool_id",
    }
)


def _strip_prod_topology_for_consolidation_validation(
    prod_custom: Dict[str, Any], validation_cluster_type: str
) -> Dict[str, Any]:
    if not validation_cluster_type.startswith("consolidation_"):
        return prod_custom
    return {
        key: value
        for key, value in prod_custom.items()
        if key not in _PROD_TOPOLOGY_KEYS_FOR_CONSOLIDATION_VALIDATION
    }


def merge_validation_cluster_args(prod_cluster: dict, validation_cluster: dict) -> dict:
    """Overlay validation.cluster on prod cluster, deep-merging custom_configurations."""
    merged = {**prod_cluster, **validation_cluster}
    prod_custom = prod_cluster.get("custom_configurations") or {}
    validation_custom = validation_cluster.get("custom_configurations") or {}
    validation_cluster_type = validation_cluster.get("type", "")
    prod_custom = _strip_prod_topology_for_consolidation_validation(
        prod_custom, validation_cluster_type
    )
    if prod_custom or validation_custom:
        merged["custom_configurations"] = {**prod_custom, **validation_custom}
    return merged
