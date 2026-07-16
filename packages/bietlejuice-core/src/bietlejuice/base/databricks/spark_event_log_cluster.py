import copy
from typing import Any, Dict, Optional


def _effective_spark_conf(cluster_configuration: dict) -> Dict[str, Any]:
    spark_conf = dict(cluster_configuration.get("spark_conf") or {})
    custom_configurations = cluster_configuration.get("custom_configurations") or {}
    custom_spark_conf = custom_configurations.get("spark_conf")
    if isinstance(custom_spark_conf, dict):
        spark_conf = {**spark_conf, **custom_spark_conf}
    return spark_conf


def apply_shard_event_log_dir_suffix(
    cluster_configuration: dict,
    *,
    execute_job_cluster_local_id: Optional[int],
) -> dict:
    """Append ``/cluster-{N}`` to ``spark.eventLog.dir`` for multi-shard DAGs.

    Each execute-job-cluster shard gets a unique event-log prefix so parallel
    clusters do not collide on ``eventlog_v2_app-*`` directories when Spark
    assigns the same application id. ``dag_id`` remains the first path segment
    after ``spark-event-logs/`` for downstream enrichment.
    """
    cluster_configuration = copy.deepcopy(cluster_configuration)
    spark_conf = _effective_spark_conf(cluster_configuration)

    if spark_conf.get("spark.eventLog.enabled") == "false":
        return cluster_configuration

    event_log_dir = spark_conf.get("spark.eventLog.dir")
    if not event_log_dir:
        return cluster_configuration

    cluster_index = execute_job_cluster_local_id or 1
    suffix = f"/cluster-{cluster_index}"
    normalized_dir = event_log_dir.rstrip("/")
    if normalized_dir.endswith(suffix):
        return cluster_configuration

    spark_conf["spark.eventLog.dir"] = f"{normalized_dir}{suffix}"
    cluster_configuration["spark_conf"] = spark_conf
    return cluster_configuration


def apply_validation_event_log_overrides(cluster_configuration: dict) -> dict:
    """Disable Spark event logging for cluster-validation DAG runs."""
    spark_conf: Dict[str, Any] = dict(cluster_configuration.get("spark_conf") or {})
    spark_conf["spark.eventLog.enabled"] = "false"
    return {**cluster_configuration, "spark_conf": spark_conf}
