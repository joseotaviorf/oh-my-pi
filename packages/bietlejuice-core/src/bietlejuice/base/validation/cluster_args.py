from typing import Any, Dict, Tuple

# Preset-name prefixes that identify consolidation validation presets.
# wonka_consolidation_* = consolidation twin + wonka runtime (see
# bietlejuice-core conf "Wonka Consolidation Presets" section).
CONSOLIDATION_PRESET_TYPE_PREFIXES: Tuple[str, ...] = (
    "wonka_consolidation_",
    "consolidation_",
)

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

_DATABRICKS_ONLY_CUSTOM_CONFIG_KEYS = frozenset(
    {
        "node_type_id",
        "driver_node_type_id",
        "master_node_type_id",
        "task_node_type_id",
        "num_workers",
        "runtime_engine",
        "instance_pool_id",
        "driver_instance_pool_id",
        "autoscale",
        "spark_version",
        "data_security_mode",
        "single_user_name",
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


def _is_databricks_to_emr_validation(
    prod_cluster_type: str, validation_cluster_type: str
) -> bool:
    return not str(prod_cluster_type).startswith("emr_") and str(
        validation_cluster_type
    ).startswith("emr_")


def _is_emr_to_databricks_validation(
    prod_cluster_type: str, validation_cluster_type: str
) -> bool:
    return prod_cluster_type.startswith("emr_") and validation_cluster_type.startswith(
        CONSOLIDATION_PRESET_TYPE_PREFIXES
    )


def _strip_databricks_only_custom_config_keys(custom: Dict[str, Any]) -> Dict[str, Any]:
    return {
        key: value
        for key, value in custom.items()
        if key not in _DATABRICKS_ONLY_CUSTOM_CONFIG_KEYS
    }


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


# Delta OSS defines every session conf under this prefix
# (DeltaSQLConf.SQL_CONF_PREFIX in delta-io/delta), so Delta tuning must survive
# the Databricks → EMR hop. Everything else under spark.databricks. is
# Databricks-platform-only (Unity Catalog, cluster profile, behaviorChange).
DATABRICKS_SPARK_CONF_PREFIX = "spark.databricks."
OSS_DELTA_SPARK_CONF_PREFIX = "spark.databricks.delta."
# Delta-prefixed but absent from Delta OSS 3.3.x DeltaSQLConf: a Databricks
# Runtime-exclusive feature. Forwarding it to EMR is a silent no-op that
# misleads anyone reading the cluster's spark-defaults.
# Mirrored in emr_plugin/template_translator.py (that package intentionally has
# no bietlejuice dependency).
DATABRICKS_PROPRIETARY_DELTA_SPARK_CONF_KEYS = frozenset(
    {"spark.databricks.delta.merge.enableLowShuffle"}
)


def is_databricks_only_spark_conf_key(key: str) -> bool:
    """True when a spark_conf key must not reach an EMR cluster."""
    name = str(key)
    if name in DATABRICKS_PROPRIETARY_DELTA_SPARK_CONF_KEYS:
        return True
    if name.startswith(OSS_DELTA_SPARK_CONF_PREFIX):
        return False
    return name.startswith(DATABRICKS_SPARK_CONF_PREFIX)


def strip_databricks_only_spark_conf(spark_conf: Any) -> Dict[str, Any]:
    """Drop Databricks-platform-only keys, keeping OSS Delta settings."""
    if not isinstance(spark_conf, dict):
        return {}
    return {
        key: value
        for key, value in spark_conf.items()
        if not is_databricks_only_spark_conf_key(key)
    }


def _strip_prod_topology_for_consolidation_validation(
    prod_custom: Dict[str, Any],
    validation_cluster_type: str,
    prod_cluster_type: str = "",
) -> Dict[str, Any]:
    if not validation_cluster_type.startswith(CONSOLIDATION_PRESET_TYPE_PREFIXES):
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


def validation_cluster_has_distinguishing_overrides(
    prod_cluster: dict, validation_cluster: dict
) -> bool:
    """Return True when validation.cluster adds overrides beyond matching prod preset type."""
    validation_custom = validation_cluster.get("custom_configurations")
    if validation_custom:
        return True

    for key, value in validation_cluster.items():
        if key == "type":
            continue
        if prod_cluster.get(key) != value:
            return True
    return False


def merge_validation_cluster_args(prod_cluster: dict, validation_cluster: dict) -> dict:
    """Overlay validation.cluster on prod cluster, deep-merging custom_configurations."""
    merged = {**prod_cluster, **validation_cluster}
    prod_custom = prod_cluster.get("custom_configurations") or {}
    validation_custom = validation_cluster.get("custom_configurations") or {}
    prod_cluster_type = prod_cluster.get("type", "")
    validation_cluster_type = validation_cluster.get("type", "")
    if _is_databricks_to_emr_validation(prod_cluster_type, validation_cluster_type):
        merged.pop("databricks_conn_id", None)
        prod_custom = _strip_databricks_only_custom_config_keys(prod_custom)
        prod_spark_conf = prod_custom.get("spark_conf")
        if isinstance(prod_spark_conf, dict):
            stripped_spark_conf = strip_databricks_only_spark_conf(prod_spark_conf)
            if stripped_spark_conf:
                prod_custom = {**prod_custom, "spark_conf": stripped_spark_conf}
            else:
                prod_custom = {
                    key: value
                    for key, value in prod_custom.items()
                    if key != "spark_conf"
                }
    else:
        prod_custom = _strip_prod_topology_for_consolidation_validation(
            prod_custom, validation_cluster_type, prod_cluster_type
        )
    # Empty validation custom means "preset defaults only". Do not inherit prod's
    # explicit PHOTON engine — consolidation presets default to STANDARD unless
    # validation.cluster re-states runtime_engine (see rightsizing disable_photon).
    if (
        validation_cluster_type.startswith(CONSOLIDATION_PRESET_TYPE_PREFIXES)
        and not validation_custom
    ):
        prod_custom = {
            key: value for key, value in prod_custom.items() if key != "runtime_engine"
        }
    if (
        validation_cluster_type.startswith(CONSOLIDATION_PRESET_TYPE_PREFIXES)
        and not validation_cluster_type.endswith("_single_node_cluster")
        and "num_workers" not in validation_custom
    ):
        prod_custom = {
            key: value for key, value in prod_custom.items() if key != "num_workers"
        }
    if prod_custom or validation_custom:
        merged_custom = {**prod_custom, **validation_custom}
        # Deep-merge spark_conf: validation settings override prod, but prod keys
        # not present in validation are preserved (e.g. spark.sql.session.timeZone).
        prod_spark_conf = prod_custom.get("spark_conf")
        validation_spark_conf = validation_custom.get("spark_conf")
        if isinstance(prod_spark_conf, dict) and isinstance(
            validation_spark_conf, dict
        ):
            merged_custom["spark_conf"] = {**prod_spark_conf, **validation_spark_conf}
        merged["custom_configurations"] = merged_custom
    else:
        merged.pop("custom_configurations", None)
    return merged
