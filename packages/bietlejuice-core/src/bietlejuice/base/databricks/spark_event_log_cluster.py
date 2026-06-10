from typing import Any, Dict


def apply_validation_event_log_overrides(cluster_configuration: dict) -> dict:
    """Disable Spark event logging for cluster-validation DAG runs."""
    spark_conf: Dict[str, Any] = dict(cluster_configuration.get("spark_conf") or {})
    spark_conf["spark.eventLog.enabled"] = "false"
    return {**cluster_configuration, "spark_conf": spark_conf}
