"""Resolve merged cluster YAML and detect Airflow EMR vs Databricks job cluster mode."""

from __future__ import annotations

from typing import Any, Dict, Tuple

from bietlejuice.services.configuration_service import ConfigurationService


def merge_cluster_configuration(
    cluster_args: Dict[str, Any], config_service: ConfigurationService
) -> Dict[str, Any]:
    cluster_type = cluster_args.get("type")
    cluster_configuration = config_service.get_config(cluster_type)
    return config_service._deep_update(
        cluster_configuration, cluster_args.get("custom_configurations", {})
    )


def is_airflow_emr_cluster(spark_version: str) -> bool:
    if not spark_version:
        return False
    return str(spark_version).lower().startswith("emr-")


def resolve_airflow_compute_mode(
    cluster_args: Dict[str, Any], config_service: ConfigurationService
) -> Tuple[bool, Dict[str, Any]]:
    merged = merge_cluster_configuration(cluster_args, config_service)
    return is_airflow_emr_cluster(merged.get("spark_version", "")), merged
