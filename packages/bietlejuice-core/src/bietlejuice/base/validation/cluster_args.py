from typing import Any, Dict

# Prod instance topology must not leak into consolidation validation clusters;
# validation custom_configurations and preset defaults define Graviton types.
_PROD_TOPOLOGY_KEYS_FOR_CONSOLIDATION_VALIDATION = frozenset(
    {
        "node_type_id",
        "driver_node_type_id",
        "master_node_type_id",
        "task_node_type_id",
        "instance_pool_id",
        "driver_instance_pool_id",
    }
)
# EMR-only keys (see dag_cluster_validator._EMR_ONLY_CUSTOM_CONFIG_KEYS).
_EMR_ONLY_CUSTOM_CONFIG_KEYS = frozenset(
    {
        "num_task_workers",
        "task_node_type_id",
        "task_availability",
        "core_nodes",
        "task_nodes",
    }
)


def _strip_emr_only_custom_config_keys(custom: Dict[str, Any]) -> Dict[str, Any]:
    stripped = {
        key: value
        for key, value in custom.items()
        if key not in _EMR_ONLY_CUSTOM_CONFIG_KEYS
    }
    aws_attrs = stripped.get("aws_attributes")
    if isinstance(aws_attrs, dict) and "task_availability" in aws_attrs:
        aws_attrs = {
            key: value for key, value in aws_attrs.items() if key != "task_availability"
        }
        if aws_attrs:
            stripped["aws_attributes"] = aws_attrs
        else:
            stripped.pop("aws_attributes", None)
    return stripped


def _is_emr_to_databricks_validation(
    prod_cluster_type: str, validation_cluster_type: str
) -> bool:
    return prod_cluster_type.startswith("emr_") and validation_cluster_type.startswith(
        "consolidation_"
    )


def _strip_prod_topology_for_consolidation_validation(
    prod_custom: Dict[str, Any],
    validation_cluster_type: str,
    prod_cluster_type: str = "",
) -> Dict[str, Any]:
    if not validation_cluster_type.startswith("consolidation_"):
        return prod_custom
    stripped = {
        key: value
        for key, value in prod_custom.items()
        if key not in _PROD_TOPOLOGY_KEYS_FOR_CONSOLIDATION_VALIDATION
    }
    if _is_emr_to_databricks_validation(prod_cluster_type, validation_cluster_type):
        stripped = _strip_emr_only_custom_config_keys(stripped)
    if validation_cluster_type.endswith("_single_node_cluster"):
        stripped = {
            key: value for key, value in stripped.items() if key != "num_workers"
        }
    return stripped


def merge_validation_cluster_args(prod_cluster: dict, validation_cluster: dict) -> dict:
    """Overlay validation.cluster on prod cluster, deep-merging custom_configurations."""
    merged = {**prod_cluster, **validation_cluster}
    prod_custom = prod_cluster.get("custom_configurations") or {}
    validation_custom = validation_cluster.get("custom_configurations") or {}
    prod_cluster_type = prod_cluster.get("type", "")
    validation_cluster_type = validation_cluster.get("type", "")
    prod_custom = _strip_prod_topology_for_consolidation_validation(
        prod_custom, validation_cluster_type, prod_cluster_type
    )
    if prod_custom or validation_custom:
        merged["custom_configurations"] = {**prod_custom, **validation_custom}
    return merged
