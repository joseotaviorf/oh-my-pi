#!/usr/bin/env python3
"""Add EMR fleet validation blocks to Databricks prod *_cluster.yml files."""

from __future__ import annotations

import argparse
import copy
import os
import sys
from pathlib import Path
from typing import Any, List, Optional

import yaml

REPO_ROOT = Path(__file__).resolve().parents[4]
_COMPILER_ROOT = Path(__file__).resolve().parents[2]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))

import re

from bietlejuice.base.airflow.cluster_config_resolver import merge_cluster_configuration
from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    emr_worker_core_task_split,
    is_emr_prod_cluster_args,
    is_single_node_cluster,
    map_instance_type_to_emr_gen6,
)
from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
    cluster_file_documents_equal,
    dump_cluster_yaml,
)
from scripts.validation.emr_fleet_conversion import (
    effective_to_fleet_topology,
    fleet_override_diff,
    strip_group_topology_keys,
)

_DATABRICKS_ONLY_CUSTOM_KEYS = frozenset(
    {
        "driver_node_type_id",
        "node_type_id",
        "master_node_type_id",
        "data_security_mode",
        "runtime_engine",
        "num_workers",
        "num_task_workers",
        "single_user_name",
        "instance_pool_id",
        "driver_instance_pool_id",
        "autoscale",
        "spark_version",
    }
)

_PEOPLE_PROFILE_MARKERS = (
    "instance_profile_secret_arn_people",
    "emr_instance_profile_arn_people",
    "people-analytics",
)

_SIZE_SUFFIX_ORDER = (
    "medium",
    "large",
    "xlarge",
    "2xlarge",
    "4xlarge",
    "8xlarge",
    "12xlarge",
    "16xlarge",
    "metal",
)

_SIZE_TO_CONSOLIDATION_TIER = {
    "medium": "xs",
    "large": "xs",
    "xlarge": "s",
    "2xlarge": "m",
    "4xlarge": "l",
    "8xlarge": "xl",
    "12xlarge": "xl",
    "16xlarge": "xl",
    "metal": "xl",
}

_CONSOLIDATION_TIER_ORDER = {"xs": 0, "s": 1, "m": 2, "l": 3, "xl": 4}

_SINGLE_NODE_FLEET_PRESET_RE = re.compile(
    r"^emr_7_12_consolidation_(xs|s|m|l|xl)_(general|memory|compute)_single_node_fleet_cluster$"
)


def _has_load_spark_job(declaration: dict) -> bool:
    workflow = declaration.get("workflow", {})
    if workflow.get("load_spark_job"):
        return True
    tables_customization = workflow.get("tables_customization")
    if not isinstance(tables_customization, dict):
        return False
    return any(
        isinstance(table_cfg, dict) and table_cfg.get("load_spark_job")
        for table_cfg in tables_customization.values()
    )


def map_to_emr_fleet_preset(prod_cluster_type: str) -> str:
    """Map consolidation_* prod preset to emr_7_12_consolidation_*_fleet_cluster."""
    cluster_type = str(prod_cluster_type)
    if not cluster_type.startswith("consolidation_"):
        raise ValueError(f"Unsupported prod cluster type: {cluster_type!r}")
    if not cluster_type.endswith("_cluster"):
        raise ValueError(f"Expected *_cluster preset: {cluster_type!r}")
    suffix = cluster_type.removeprefix("consolidation_")
    return f"emr_7_12_consolidation_{suffix.replace('_cluster', '_fleet_cluster')}"


def _is_people_instance_profile(instance_profile_arn: Any) -> bool:
    value = str(instance_profile_arn or "")
    return any(marker in value for marker in _PEOPLE_PROFILE_MARKERS)


def _instance_size_at_least(instance_type: str, minimum_size: str) -> str:
    """Bump instance type size suffix to at least minimum_size."""
    family, size = str(instance_type).rsplit(".", 1)
    size = size.lower()
    if size not in _SIZE_SUFFIX_ORDER or minimum_size not in _SIZE_SUFFIX_ORDER:
        return str(instance_type)
    if _SIZE_SUFFIX_ORDER.index(size) < _SIZE_SUFFIX_ORDER.index(minimum_size):
        return f"{family}.{minimum_size}"
    return str(instance_type)


def _consolidation_tier_for_instance_size(size_suffix: str) -> str:
    return _SIZE_TO_CONSOLIDATION_TIER.get(size_suffix.lower(), "s")


def _maybe_bump_single_node_fleet_preset(
    fleet_type: str, master_instance_type: str
) -> str:
    """Raise single-node fleet preset tier when master requires a larger consolidation tier."""
    match = _SINGLE_NODE_FLEET_PRESET_RE.match(fleet_type)
    if not match:
        return fleet_type

    master_size = master_instance_type.rsplit(".", 1)[-1].lower()
    required_tier = _consolidation_tier_for_instance_size(master_size)
    current_tier = match.group(1)
    family = match.group(2)

    if (
        _CONSOLIDATION_TIER_ORDER[required_tier]
        <= _CONSOLIDATION_TIER_ORDER[current_tier]
    ):
        return fleet_type

    return f"emr_7_12_consolidation_{required_tier}_{family}_single_node_fleet_cluster"


def _emr_minimum_instance_type(instance_type: str) -> str:
    """EMR consolidation presets use xlarge as the minimum worker size."""
    mapped = map_instance_type_to_emr_gen6(str(instance_type))
    family, size = mapped.rsplit(".", 1)
    if size == "large":
        return f"{family}.xlarge"
    return mapped


def build_emr_effective_from_databricks(
    effective_prod: dict,
    prod_cluster_type: str,
    config_service: ConfigurationService,
) -> dict[str, Any]:
    """Synthesize EMR group topology from merged Databricks prod config."""
    single_node = is_single_node_cluster(effective_prod) or "_single_node_" in str(
        prod_cluster_type
    )

    driver = (
        effective_prod.get("driver_node_type_id")
        or effective_prod.get("master_node_type_id")
        or effective_prod.get("node_type_id")
        or "r6g.xlarge"
    )
    worker = effective_prod.get("node_type_id") or driver
    master = _emr_minimum_instance_type(str(driver))
    core_type = _emr_minimum_instance_type(str(worker))
    task_type = core_type

    num_workers = effective_prod.get("num_workers")
    if num_workers is None:
        preset = config_service.get_config(prod_cluster_type)
        num_workers = (preset or {}).get("num_workers", 2)

    aws_attributes = copy.deepcopy(effective_prod.get("aws_attributes") or {})
    if not isinstance(aws_attributes, dict):
        aws_attributes = {}

    if single_node or int(num_workers or 0) == 0:
        master = _instance_size_at_least(master, "2xlarge")
        return {
            "master_node_type_id": master,
            "num_workers": 0,
            "core_nodes": {},
            "task_nodes": {},
            "aws_attributes": aws_attributes,
        }

    total = int(num_workers)
    core_count, task_count = emr_worker_core_task_split(total)
    return {
        "master_node_type_id": master,
        "num_workers": total,
        "core_nodes": {
            "node_type_id": core_type,
            "instance_count": core_count,
        },
        "task_nodes": {
            "node_type_id": task_type,
            "instance_count": task_count,
        },
        "aws_attributes": aws_attributes,
    }


def _filter_spark_conf(spark_conf: Any) -> dict[str, Any]:
    if not isinstance(spark_conf, dict):
        return {}
    return {
        key: value
        for key, value in spark_conf.items()
        if not str(key).startswith("spark.databricks.")
    }


def extract_preserved_custom_config(
    prod_cluster: dict,
    effective_prod: dict,
) -> dict[str, Any]:
    """Carry EMR-relevant prod overlays into validation custom_configurations."""
    preserved: dict[str, Any] = {}
    prod_custom = prod_cluster.get("custom_configurations") or {}
    if not isinstance(prod_custom, dict):
        prod_custom = {}

    aws: dict[str, Any] = {}
    prod_aws = prod_custom.get("aws_attributes") or {}
    if isinstance(prod_aws, dict):
        ebs = prod_aws.get("ebs_volume_size")
        if ebs is not None:
            aws["ebs_volume_size"] = ebs
        profile = prod_aws.get("instance_profile_arn")
        if _is_people_instance_profile(profile):
            aws["instance_profile_arn"] = (
                "{{ var.value.emr_instance_profile_arn_people }}"
            )
        elif profile and "emr_instance_profile" in str(profile):
            aws["instance_profile_arn"] = profile
    if aws:
        preserved["aws_attributes"] = aws

    prod_spark_conf = prod_custom.get("spark_conf")
    if isinstance(prod_spark_conf, dict) and prod_spark_conf:
        spark_conf = _filter_spark_conf(prod_spark_conf)
        preserved["spark_conf"] = spark_conf or {}

    init_scripts = prod_custom.get("init_scripts")
    if init_scripts:
        preserved["init_scripts"] = copy.deepcopy(init_scripts)

    return preserved


def _deep_merge(base: dict, overlay: dict) -> dict:
    merged = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


def _strip_databricks_only_keys(custom: dict[str, Any]) -> None:
    for key in _DATABRICKS_ONLY_CUSTOM_KEYS:
        custom.pop(key, None)


def build_validation_block(
    prod_cluster: dict,
    declaration: dict,
    config_service: ConfigurationService,
) -> Optional[dict[str, Any]]:
    """Build validation: document for a Databricks prod cluster."""
    if is_emr_prod_cluster_args(prod_cluster, config_service):
        return None

    prod_type = str(prod_cluster.get("type", ""))
    if not prod_type.startswith("consolidation_"):
        return None

    fleet_type = map_to_emr_fleet_preset(prod_type)
    effective_prod = merge_cluster_configuration(prod_cluster, config_service)
    emr_effective = build_emr_effective_from_databricks(
        effective_prod, prod_type, config_service
    )
    single_node = is_single_node_cluster(effective_prod) or "_single_node_" in prod_type
    if single_node:
        fleet_type = _maybe_bump_single_node_fleet_preset(
            fleet_type, str(emr_effective["master_node_type_id"])
        )

    preset_fleet = config_service.get_config(fleet_type)
    if not isinstance(preset_fleet, dict):
        raise ValueError(f"Unknown fleet preset: {fleet_type}")

    effective_fleet = effective_to_fleet_topology(emr_effective)
    fleet_custom = fleet_override_diff(preset_fleet, effective_fleet)
    preserved = extract_preserved_custom_config(prod_cluster, effective_prod)
    custom_configurations = _deep_merge(fleet_custom, preserved)
    strip_group_topology_keys(custom_configurations)
    _strip_databricks_only_keys(custom_configurations)

    validation_cluster: dict[str, Any] = {"type": fleet_type}
    if custom_configurations:
        validation_cluster["custom_configurations"] = custom_configurations

    validation: dict[str, Any] = {"cluster": validation_cluster}
    if _has_load_spark_job(declaration):
        validation["allow_custom_spark_job"] = True
    return validation


def find_cluster_path(
    dag_name: str, dags_root: Path = REPO_ROOT / "dags"
) -> Optional[Path]:
    matches = sorted(dags_root.rglob(f"{dag_name}/{dag_name}_cluster.yml"))
    return matches[0] if len(matches) == 1 else None


def find_declaration_path(
    dag_name: str, dags_root: Path = REPO_ROOT / "dags"
) -> Optional[Path]:
    matches = sorted(dags_root.rglob(f"{dag_name}/{dag_name}_declaration.yml"))
    return matches[0] if len(matches) == 1 else None


def apply_validation_to_cluster_file(
    cluster_path: Path,
    declaration: dict,
    config_service: ConfigurationService,
    *,
    dry_run: bool = False,
    force: bool = False,
) -> Optional[str]:
    document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        return None

    if document.get("validation") and not force:
        return "skip_has_validation"

    prod_cluster = document.get("cluster")
    if not isinstance(prod_cluster, dict):
        return None

    validation = build_validation_block(prod_cluster, declaration, config_service)
    if validation is None:
        return "skip_not_eligible"

    new_document = copy.deepcopy(document)
    new_document.pop("validation", None)
    new_document["validation"] = validation
    new_text = dump_cluster_yaml(new_document)
    assert_no_folded_catalog_namespace(new_text)
    old_text = cluster_path.read_text(encoding="utf-8")
    if cluster_file_documents_equal(old_text, new_text):
        return "skip_no_change"

    label = _display_path(cluster_path)
    if dry_run:
        print(f"Would update: {label}")
    else:
        cluster_path.write_text(new_text, encoding="utf-8")
        print(f"Updated: {label}")
    return "updated"


def _display_path(cluster_path: Path) -> str:
    try:
        return cluster_path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return cluster_path.as_posix()


def load_dag_names(path: Path) -> List[str]:
    names = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            names.append(line)
    return names


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dag-list",
        type=Path,
        help="Newline-separated DAG names (default: built-in batch list)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would change without writing",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace existing validation: blocks",
    )
    args = parser.parse_args(argv)

    os.environ.setdefault("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()
    config_service = ConfigurationService()

    if args.dag_list:
        dag_names = load_dag_names(args.dag_list)
    else:
        dag_names = DEFAULT_DAG_NAMES

    stats = {
        "updated": 0,
        "skip_has_validation": 0,
        "skip_not_eligible": 0,
        "missing": 0,
    }
    for dag_name in dag_names:
        cluster_path = find_cluster_path(dag_name)
        if cluster_path is None:
            print(f"Missing cluster file: {dag_name}", file=sys.stderr)
            stats["missing"] += 1
            continue

        decl_path = find_declaration_path(dag_name)
        declaration = (
            yaml.safe_load(decl_path.read_text(encoding="utf-8")) if decl_path else {}
        )
        if not isinstance(declaration, dict):
            declaration = {}

        result = apply_validation_to_cluster_file(
            cluster_path,
            declaration,
            config_service,
            dry_run=args.dry_run,
            force=args.force,
        )
        if result is None:
            continue
        if result not in stats:
            stats["updated"] += int(result == "updated")
        else:
            stats[result] += 1

    print(
        "Done: "
        f"updated={stats['updated']} "
        f"skip_has_validation={stats['skip_has_validation']} "
        f"skip_not_eligible={stats['skip_not_eligible']} "
        f"missing={stats['missing']}"
    )
    return 1 if stats["missing"] else 0


DEFAULT_DAG_NAMES = [
    "enrich_crm_tasks_transitions",
    "enrich_customer_demand",
    "enrich_dashboard_governance",
    "enrich_data_exposure",
    "enrich_databricks_health",
    "enrich_databricks_pricing",
    "enrich_databricks_query_history",
    "enrich_databricks_table_usage",
    "enrich_databricks_usage_costs",
    "enrich_datahub_assets",
    "enrich_date",
    "enrich_demand_score_report",
    "enrich_documentation_metrics",
    "enrich_docx",
    "enrich_dual_write",
    "enrich_ebdb_affiliates_cost",
    "enrich_ebdb_customer_contact_identification",
    "enrich_ebdb_photo_jobs",
    "enrich_ebdb_proposal",
    "enrich_ebdb_rental_administration",
    "enrich_ebdb_smart_price",
    "enrich_emlio",
    "enrich_eval_model_seamless",
    "enrich_facebook_insights",
    "enrich_fairness_assessment",
    "enrich_fintech_snapshot",
    "enrich_golden_set",
    "enrich_google_analytics_classified",
    "enrich_hefesto",
    "enrich_hightouch",
    "enrich_hiring",
    "enrich_house_feature_inference",
    "enrich_hr_system_custom",
    "enrich_inspections_metrics",
    "enrich_internal_chat",
    "enrich_iptu",
    "enrich_kill_queue",
    "enrich_kodak",
    "enrich_kong",
    "enrich_kong_ss",
    "enrich_lead",
    "enrich_lead_tracking",
    "enrich_learning",
    "enrich_legaut",
    "enrich_listing_flow",
    "enrich_listing_temp",
    "enrich_losses",
    "enrich_lost_listings",
    "enrich_marketing_automatic_daily_costs",
    "enrich_marketing_costs_offline",
    "enrich_marketing_manual_daily_costs",
    "enrich_monopoly",
    "enrich_nexxera",
    "enrich_nps_answer_drivers",
    "enrich_nps_quintocred",
    "enrich_online_attribution",
    "enrich_open_external_data_addresses",
    "enrich_pixar",
    "enrich_planner_emlio_logs",
    "enrich_pricing_agent",
    "enrich_proposal",
    "enrich_region",
    "enrich_rent_flows",
    "enrich_rent_potential_listing",
    "enrich_rental_guarantee",
    "enrich_reverses_monitoring",
    "enrich_robin_hood",
    "enrich_sale_available_booking_hours",
    "enrich_sale_demand_events",
    "enrich_sale_firestore",
    "enrich_sale_listing_demand",
    "enrich_sale_potential_listing",
    "enrich_sap_gateway",
    "enrich_search_session_event",
    "enrich_seo_funnel",
    "enrich_similarity_score",
    "enrich_sonia_ht",
    "enrich_spark_event_logs",
    "enrich_stale_dags",
    "enrich_static_files",
    "enrich_static_files_ss",
    "enrich_support_and_service_kpis_targets",
    "enrich_ticket_rate_classification_snapshot",
    "enrich_top_of_funnel_affiliates",
    "enrich_top_of_funnel_demand",
    "enrich_top_of_funnel_supply",
    "enrich_tracksale_dispatches",
    "enrich_transactional_entities_test",
    "enrich_trino",
    "enrich_trino_costs",
    "enrich_user",
    "enrich_viva_real_crawler_listings",
    "enrich_wololo",
    "identitynow",
    "istio",
    "metric_observability__dags",
    "metric_people",
    "metric_rent__demand_events",
    "metric_rent__demand_targets",
    "metric_rent__gross_profit",
    "metric_rent__nps",
    "metric_rent__tickets",
    "metric_sale__experiment",
    "opa",
    "vault",
]


if __name__ == "__main__":
    raise SystemExit(main())
