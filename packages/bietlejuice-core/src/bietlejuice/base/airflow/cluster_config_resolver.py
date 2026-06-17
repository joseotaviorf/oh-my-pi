"""Resolve merged cluster YAML and detect Airflow EMR vs Databricks job cluster mode.

Airflow-only keys may appear in the merged cluster dict (preset or declaration
``custom_configurations``) and are stripped in ``EmrJobClusterEngine`` before EMR
translation — for example ``airflow_emr_create_cluster_deferrable`` (bool) for the
create-cluster operator's deferrable wait behaviour.
"""

from __future__ import annotations

import copy
from typing import Any, Dict, Tuple

from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args
from bietlejuice.services.configuration_service import ConfigurationService


def merge_cluster_configuration(
    cluster_args: Dict[str, Any], config_service: ConfigurationService
) -> Dict[str, Any]:
    cluster_type = cluster_args.get("type")
    cluster_configuration = copy.deepcopy(config_service.get_config(cluster_type))
    return config_service._deep_update(
        cluster_configuration, cluster_args.get("custom_configurations", {})
    )


def validation_resolves_to_prod_spec(
    prod_cluster: Dict[str, Any],
    validation_cluster: Dict[str, Any],
    config_service: ConfigurationService,
) -> bool:
    """True when the validation cluster resolves to the same effective spec as prod.

    Compares fully-merged cluster configurations (preset defaults + overlaid
    custom_configurations via merge_validation_cluster_args) so a validation that
    re-states prod's running spec is detected as a no-op even when the YAML text
    or preset name differs. Raises IndexError if either cluster type is not a
    registered preset (caller decides how to handle).
    """
    effective_prod = merge_cluster_configuration(prod_cluster, config_service)
    effective_validation = merge_cluster_configuration(
        merge_validation_cluster_args(prod_cluster, validation_cluster),
        config_service,
    )
    return effective_validation == effective_prod


def is_airflow_emr_cluster(spark_version: str) -> bool:
    if not spark_version:
        return False
    return str(spark_version).lower().startswith("emr-")


def resolve_airflow_compute_mode(
    cluster_args: Dict[str, Any], config_service: ConfigurationService
) -> Tuple[bool, Dict[str, Any]]:
    merged = merge_cluster_configuration(cluster_args, config_service)
    return is_airflow_emr_cluster(merged.get("spark_version", "")), merged
