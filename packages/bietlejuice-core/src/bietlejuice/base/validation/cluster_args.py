def merge_validation_cluster_args(prod_cluster: dict, validation_cluster: dict) -> dict:
    """Overlay validation.cluster on prod cluster, deep-merging custom_configurations."""
    merged = {**prod_cluster, **validation_cluster}
    prod_custom = prod_cluster.get("custom_configurations") or {}
    validation_custom = validation_cluster.get("custom_configurations") or {}
    if prod_custom or validation_custom:
        merged["custom_configurations"] = {**prod_custom, **validation_custom}
    return merged
