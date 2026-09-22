"""Resolve merged cluster YAML and detect Airflow EMR vs Databricks job cluster mode.

Airflow-only keys may appear in the merged cluster dict (preset or declaration
``custom_configurations``) and are stripped in ``EmrJobClusterEngine`` before EMR
translation — for example ``airflow_emr_create_cluster_deferrable`` (bool) to
opt out of deferrable wait behaviour on EMR Airflow operators (default is deferrable).
"""

from __future__ import annotations

import copy
from collections.abc import Mapping
from typing import Any, Dict, Tuple

from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args
from bietlejuice.services.configuration_service import ConfigurationService

# DAGs opted out of generated validation.cluster and cluster-diff checks
# (e.g. custom Spark jobs without cluster_validation write support yet, or prod
# already matches its consolidation preset).
CLUSTER_VALIDATION_EXCLUDED_DAGS = frozenset(
    {"reverse_kyc", "enrich_search", "enrich_tars"}
)


def prune_empty_mappings(overrides: Mapping[str, Any]) -> Dict[str, Any]:
    """Drop empty-mapping values so they no-op instead of wiping preset defaults.

    ``HierarchicalConf._deep_update`` only recurses into *truthy* mappings
    (``if isinstance(value, Mapping) and value``); an empty dict falls through to
    plain assignment and replaces the preset's nested block wholesale. A
    declaration writing ``spark_conf: {}`` means "no extra spark conf", not "drop
    the preset's spark_conf" — the latter silently strips
    ``spark.sql.catalogImplementation: hive`` (breaking Glue resolution for
    non-Delta tables) along with every driver/executor override.
    """
    pruned: Dict[str, Any] = {}
    for key, value in overrides.items():
        if isinstance(value, Mapping):
            nested = prune_empty_mappings(value)
            if not nested:
                continue
            pruned[key] = nested
        else:
            pruned[key] = value
    return pruned


def apply_custom_configurations(
    cluster_configuration: Dict[str, Any],
    custom_configurations: Mapping[str, Any],
    config_service: ConfigurationService,
) -> Dict[str, Any]:
    """Deep-merge ``custom_configurations`` into an already-resolved cluster preset.

    Use this instead of calling ``_deep_update`` directly so empty mappings stay
    no-ops (see :func:`prune_empty_mappings`).
    """
    return config_service._deep_update(
        cluster_configuration, prune_empty_mappings(custom_configurations or {})
    )


def merge_cluster_configuration(
    cluster_args: Dict[str, Any], config_service: ConfigurationService
) -> Dict[str, Any]:
    cluster_type = cluster_args.get("type")
    cluster_configuration = copy.deepcopy(config_service.get_config(cluster_type))
    return apply_custom_configurations(
        cluster_configuration,
        cluster_args.get("custom_configurations", {}),
        config_service,
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


def is_airflow_emr_cluster_type(cluster_type: str) -> bool:
    """True when the declared preset name is an EMR cluster (emr_*)."""
    return str(cluster_type or "").startswith("emr_")


def resolve_airflow_compute_mode(
    cluster_args: Dict[str, Any], config_service: ConfigurationService
) -> Tuple[bool, Dict[str, Any]]:
    merged = merge_cluster_configuration(cluster_args, config_service)
    # Prefer preset type over spark_version: leftover Databricks spark_version in
    # custom_configurations must not route an emr_* cluster through Databricks.
    use_emr = is_airflow_emr_cluster_type(
        cluster_args.get("type", "")
    ) or is_airflow_emr_cluster(merged.get("spark_version", ""))
    return use_emr, merged
