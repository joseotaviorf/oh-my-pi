"""
Instance-topology mapping from effective prod cluster config to consolidation validation presets.

Resolves prod cluster args via merge_cluster_configuration (same as runtime), maps legacy
instance types to Graviton equivalents, and selects a consolidation_* preset from prod_conf.
"""

from __future__ import annotations

import copy
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from bietlejuice.base.airflow.cluster_config_resolver import merge_cluster_configuration
from bietlejuice.base.paths import BIETLEJUICE_CONFIG_ROOT
from bietlejuice.services.configuration_service import ConfigurationService

# Eligibility aligned with scripts/list_cluster_validation_eligible_dags.py
PHASE1_WORKFLOWS = frozenset({"query_delta", "query", "dw_query", "metric_query"})
PHASE2_WORKFLOWS = frozenset(
    {
        "cdc",
        "custom_ingestion",
        "gsheets",
        "database_pull",
        "database_pull_delta",
        "api_ingestion",
        "dms_cdc",
        "core_model",
        "access",
        "load",
        "load_access",
        "reverse",
        "qube_measure",
        "qube_dimension",
        "qube_metric",
    }
)
SKIP_CLUSTER_PREFIXES = ("emr_",)

# DAGs opted out of generated validation.cluster (e.g. custom Spark jobs without
# cluster_validation write support yet).
CLUSTER_VALIDATION_EXCLUDED_DAGS = frozenset({"reverse_kyc"})

INSTANCE_SUFFIX_TO_TIER = {
    "large": "xs",
    "xlarge": "s",
    "2xlarge": "m",
    "4xlarge": "l",
    "8xlarge": "xl",
    "9xlarge": "xl",
    "12xlarge": "xl",
}

# Valid Graviton2 gen-6 sizes (shared by m6g/r6g/c6g and m6gd/r6gd/c6gd).
GRAVITON_VALID_SUFFIXES = frozenset(
    {
        "medium",
        "large",
        "xlarge",
        "2xlarge",
        "4xlarge",
        "8xlarge",
        "12xlarge",
        "16xlarge",
        "metal",
    }
)

TIER_TO_CONSOLIDATION_GRAVITON_SUFFIX = {
    "xs": "large",
    "s": "xlarge",
    "m": "2xlarge",
    "l": "4xlarge",
    "xl": "8xlarge",
}

GRAVITON_FAMILY_PREFIX = {
    "general": "m6g",
    "memory": "r6g",
    "compute": "c6g",
}

GRAVITON_NVME_FAMILY_PREFIX = {
    "general": "m6gd",
    "memory": "r6gd",
    "compute": "c6gd",
}

SIZE_TIER_ORDER = ("xs", "s", "m", "l", "xl")

CONSOLIDATION_PRESET_RE = re.compile(
    r"^consolidation_(xs|s|m|l|xl)_(general|memory|compute)"
    r"(?:_single_node)?_cluster$"
)

CONSOLIDATION_PRESET_NAMES_RE = re.compile(
    r"^(consolidation_[a-z0-9_]+):", re.MULTILINE
)

GENERAL_PREFIXES = ("m-fleet", "m5", "m5a", "m5d", "m6g", "m6i", "m7a", "m7g", "m7i")
MEMORY_PREFIXES = ("r4", "r5", "r5a", "r5d", "r6g", "r6i", "r7a", "r7g", "r7i")
COMPUTE_PREFIXES = ("c5", "c5a", "c5n", "c6g", "c6i", "c7i")


@dataclass(frozen=True)
class ConsolidationPreset:
    name: str
    family: str
    size_tier: str
    is_single_node: bool
    node_type_id: Optional[str]
    driver_node_type_id: Optional[str]
    master_node_type_id: Optional[str]
    num_workers: Optional[int]
    spark_version: Optional[str]


@dataclass(frozen=True)
class ValidationClusterSpec:
    cluster_type: str
    custom_configurations: Dict[str, Any]
    databricks_conn_id: Optional[str] = None
    access_control_list: Any = None
    custom_libraries: Any = None
    allow_custom_spark_job: bool = False


def _has_load_spark_job(declaration: dict) -> bool:
    workflow = declaration.get("workflow", {})
    if workflow.get("load_spark_job"):
        return True
    tables_customization = workflow.get("tables_customization")
    if not isinstance(tables_customization, dict):
        return False
    for table_cfg in tables_customization.values():
        if isinstance(table_cfg, dict) and table_cfg.get("load_spark_job"):
            return True
    return False


def validation_eligibility_label(declaration: dict) -> Optional[str]:
    """Return eligibility label or None if validation block should be omitted."""
    dag_name = (declaration.get("dag") or {}).get("name")
    if dag_name in CLUSTER_VALIDATION_EXCLUDED_DAGS:
        return None
    cluster_type = (declaration.get("cluster") or {}).get("type", "")
    if cluster_type.startswith(SKIP_CLUSTER_PREFIXES):
        return None
    workflow_type = declaration.get("workflow", {}).get("type", "")
    if workflow_type in PHASE1_WORKFLOWS:
        if _has_load_spark_job(declaration):
            return "phase1_needs_allow_custom_spark_job"
        return "phase1"
    if workflow_type in PHASE2_WORKFLOWS:
        return "phase2"
    return None


def is_emr_effective_config(effective: dict) -> bool:
    spark_version = str(effective.get("spark_version", "")).lower()
    return spark_version.startswith("emr-")


def _instance_family(instance_type: str) -> str:
    base = instance_type.split(".", 1)[0].lower()
    for prefix in GENERAL_PREFIXES:
        if base == prefix or base.startswith(prefix):
            return "general"
    for prefix in MEMORY_PREFIXES:
        if base == prefix or base.startswith(prefix):
            return "memory"
    for prefix in COMPUTE_PREFIXES:
        if base == prefix or base.startswith(prefix):
            return "compute"
    raise ValueError(f"Unrecognized instance family for type {instance_type!r}")


def _instance_size_suffix(instance_type: str) -> str:
    if "." not in instance_type:
        raise ValueError(f"Invalid instance type (no size suffix): {instance_type!r}")
    suffix = instance_type.split(".", 1)[1].lower()
    if suffix not in INSTANCE_SUFFIX_TO_TIER:
        raise ValueError(f"Unrecognized instance size suffix: {suffix!r}")
    return suffix


VALIDATION_DRIVER_OVERSIZED_SUFFIXES = frozenset(
    {"4xlarge", "8xlarge", "12xlarge", "16xlarge", "metal"}
)


def cap_validation_driver_node_type(node_type_id: Optional[str]) -> Optional[str]:
    """Cap validation driver to 2xlarge (64 GiB) for smoke-test cost and fleet limits."""
    if not node_type_id:
        return node_type_id
    suffix = _instance_size_suffix(node_type_id)
    if suffix not in VALIDATION_DRIVER_OVERSIZED_SUFFIXES:
        return node_type_id
    prefix = node_type_id.rsplit(".", 1)[0]
    return f"{prefix}.2xlarge"


def _graviton_suffix_for_instance_type(instance_type: str) -> str:
    """Map prod size suffix to a valid Graviton gen-6 size (snap down aberrant sizes)."""
    prod_suffix = _instance_size_suffix(instance_type)
    if prod_suffix in GRAVITON_VALID_SUFFIXES:
        return prod_suffix
    tier = INSTANCE_SUFFIX_TO_TIER[prod_suffix]
    return TIER_TO_CONSOLIDATION_GRAVITON_SUFFIX[tier]


def _uses_photon(effective_prod: dict, prod_cluster_type: str) -> bool:
    if str(effective_prod.get("runtime_engine", "")).upper() == "PHOTON":
        return True
    return "photon" in prod_cluster_type.lower()


def map_instance_type_to_graviton(instance_type: str, *, use_nvme: bool = False) -> str:
    """Map legacy/x86/fleet instance type to Graviton consolidation equivalent."""
    if not instance_type:
        raise ValueError("Empty instance type")
    family = _instance_family(instance_type)
    graviton_suffix = _graviton_suffix_for_instance_type(instance_type)
    prefix_map = GRAVITON_NVME_FAMILY_PREFIX if use_nvme else GRAVITON_FAMILY_PREFIX
    graviton_prefix = prefix_map[family]
    return f"{graviton_prefix}.{graviton_suffix}"


def map_optional_instance_type(
    instance_type: Optional[str], *, use_nvme: bool = False
) -> Optional[str]:
    if not instance_type:
        return None
    return map_instance_type_to_graviton(str(instance_type), use_nvme=use_nvme)


_DATABRICKS_TOPOLOGY_FLAT_KEYS = (
    "node_type_id",
    "driver_node_type_id",
    "task_node_type_id",
)
_DATABRICKS_TOPOLOGY_NESTED_KEYS = (
    ("core_nodes", "node_type_id"),
    ("task_nodes", "node_type_id"),
)


def _map_topology_value(instance_type: str, *, use_nvme: bool) -> str:
    return map_instance_type_to_graviton(str(instance_type), use_nvme=use_nvme)


def normalize_emr_cluster_topology(cluster_args: dict) -> dict:
    """
    Ensure EMR worker-count overrides live under core_nodes/task_nodes.instance_count.

    EMR merge and validation read task_nodes.instance_count (task workers may be 0).
    Legacy flat instance_count, num_workers, and num_task_workers are rewritten here.
    """
    normalized = copy.deepcopy(cluster_args)
    custom = normalized.get("custom_configurations")
    if not isinstance(custom, dict):
        return normalized

    flat_count = custom.pop("instance_count", None)
    if flat_count is not None:
        task_nodes = custom.setdefault("task_nodes", {})
        if isinstance(task_nodes, dict) and "instance_count" not in task_nodes:
            task_nodes["instance_count"] = int(flat_count)

    num_workers = custom.get("num_workers")
    num_task_workers = custom.get("num_task_workers")

    if num_task_workers is not None:
        custom.pop("num_task_workers", None)
        task_nodes = custom.setdefault("task_nodes", {})
        if isinstance(task_nodes, dict) and "instance_count" not in task_nodes:
            task_nodes["instance_count"] = int(num_task_workers)

    if num_workers is not None and num_task_workers is not None:
        custom.pop("num_workers", None)
        core_count = int(num_workers) - int(num_task_workers)
        core_nodes = custom.setdefault("core_nodes", {})
        if isinstance(core_nodes, dict) and "instance_count" not in core_nodes:
            core_nodes["instance_count"] = max(core_count, 1)

    return normalized


def normalize_databricks_cluster_topology(
    cluster_args: dict,
    config_service: Optional[ConfigurationService] = None,
) -> dict:
    """
    Rewrite Databricks cluster topology overrides to Graviton gen-6 (m6g/r6g/c6g or *gd).

    Uses the same mapping as validation preset selection. EMR clusters are returned unchanged.
    """
    service = config_service or ConfigurationService()
    normalized = copy.deepcopy(cluster_args)
    effective = merge_cluster_configuration(normalized, service)
    if is_emr_effective_config(effective):
        return normalize_emr_cluster_topology(normalized)

    cluster_type = str(normalized.get("type", ""))
    use_nvme = _uses_photon(effective, cluster_type)
    custom = normalized.get("custom_configurations")
    if not isinstance(custom, dict):
        return normalized

    for key in _DATABRICKS_TOPOLOGY_FLAT_KEYS:
        value = custom.get(key)
        if value:
            custom[key] = _map_topology_value(str(value), use_nvme=use_nvme)

    for parent_key, child_key in _DATABRICKS_TOPOLOGY_NESTED_KEYS:
        section = custom.get(parent_key)
        if isinstance(section, dict) and section.get(child_key):
            section[child_key] = _map_topology_value(
                str(section[child_key]), use_nvme=use_nvme
            )

    return normalized


def size_tier_from_instance_type(instance_type: str) -> str:
    return INSTANCE_SUFFIX_TO_TIER[_instance_size_suffix(instance_type)]


def is_single_node_cluster(effective: dict) -> bool:
    num_workers = effective.get("num_workers")
    if num_workers is not None and int(num_workers) == 0:
        return True
    spark_conf = effective.get("spark_conf") or {}
    if isinstance(spark_conf, dict):
        profile = spark_conf.get("spark.databricks.cluster.profile", "")
        if str(profile).lower() == "singlenode":
            return True
    custom_tags = effective.get("custom_tags") or {}
    if isinstance(custom_tags, dict):
        resource_class = custom_tags.get("ResourceClass", "")
        if str(resource_class) == "SingleNode":
            return True
    return False


def _list_consolidation_preset_names() -> List[str]:
    prod_conf_path = Path(BIETLEJUICE_CONFIG_ROOT) / "prod_conf.yml"
    content = prod_conf_path.read_text(encoding="utf-8")
    names = CONSOLIDATION_PRESET_NAMES_RE.findall(content)
    return sorted(set(names))


def build_consolidation_catalog(
    config_service: Optional[ConfigurationService] = None,
) -> List[ConsolidationPreset]:
    service = config_service or ConfigurationService()
    catalog: List[ConsolidationPreset] = []
    for name in _list_consolidation_preset_names():
        match = CONSOLIDATION_PRESET_RE.match(name)
        if not match:
            continue
        resolved = service.get_config(name)
        size_tier, family = match.group(1), match.group(2)
        is_single_node = "_single_node" in name
        topology_master = resolved.get("master_node_type_id") or resolved.get(
            "driver_node_type_id"
        )
        catalog.append(
            ConsolidationPreset(
                name=name,
                family=family,
                size_tier=size_tier,
                is_single_node=is_single_node,
                node_type_id=resolved.get("node_type_id"),
                driver_node_type_id=topology_master,
                master_node_type_id=topology_master,
                num_workers=resolved.get("num_workers"),
                spark_version=resolved.get("spark_version"),
            )
        )
    return catalog


def _topology_from_mapped_worker(mapped_worker: str) -> Tuple[str, str]:
    family = _instance_family(mapped_worker)
    size_tier = size_tier_from_instance_type(mapped_worker)
    return family, size_tier


def _mapped_worker_and_driver(
    effective_prod: dict, prod_cluster_type: str
) -> Tuple[str, Optional[str]]:
    use_nvme = _uses_photon(effective_prod, prod_cluster_type)
    mapped_worker = map_instance_type_to_graviton(
        _infer_logical_instance_type(effective_prod, prod_cluster_type),
        use_nvme=use_nvme,
    )
    driver_raw = effective_prod.get("master_node_type_id") or effective_prod.get(
        "driver_node_type_id"
    )
    if not driver_raw and (
        effective_prod.get("driver_instance_pool_id")
        or effective_prod.get("instance_pool_id")
    ):
        driver_raw = _infer_logical_instance_type(effective_prod, prod_cluster_type)
    mapped_driver = map_optional_instance_type(
        str(driver_raw) if driver_raw is not None else None,
        use_nvme=use_nvme,
    )
    return mapped_worker, mapped_driver


def _is_homogeneous_topology(mapped_worker: str, mapped_driver: Optional[str]) -> bool:
    if mapped_driver is None:
        return True
    return mapped_worker == mapped_driver


def _presets_matching_worker_topology(
    catalog: List[ConsolidationPreset],
    *,
    family: str,
    single_node: bool,
    mapped_worker: str,
    mapped_driver: Optional[str],
    homogeneous: bool,
) -> List[ConsolidationPreset]:
    pool = [
        preset
        for preset in catalog
        if preset.family == family
        and preset.is_single_node == single_node
        and preset.node_type_id == mapped_worker
    ]
    if homogeneous and mapped_driver is not None:
        pool = [
            preset for preset in pool if preset.driver_node_type_id == mapped_driver
        ]
    return pool


def _infer_logical_instance_type(effective_prod: dict, prod_cluster_type: str) -> str:
    """Resolve worker instance type when prod uses pools instead of node_type_id."""
    worker = effective_prod.get("node_type_id")
    if worker:
        return str(worker)

    preset_lower = prod_cluster_type.lower()
    if "rfleet" in preset_lower or "fleet" in preset_lower:
        for suffix in ("8xlarge", "4xlarge", "2xlarge", "xlarge", "large"):
            if suffix in preset_lower:
                return f"m-fleet.{suffix}"
        return "m-fleet.xlarge"

    pool_keys = (
        effective_prod.get("instance_pool_id"),
        effective_prod.get("driver_instance_pool_id"),
    )
    pool_blob = " ".join(str(value) for value in pool_keys if value).lower()
    if "rfleet_xlarge" in pool_blob or "fleet_xlarge" in pool_blob:
        return "m-fleet.xlarge"

    raise ValueError(
        f"Effective prod cluster for {prod_cluster_type!r} has no node_type_id "
        "and instance topology could not be inferred from preset name or pools"
    )


def _values_equal(left: Any, right: Any) -> bool:
    """True when prod and validation preset values are equivalent."""
    if left is None and right is None:
        return True
    if left is None or right is None:
        return False
    if isinstance(left, (int, float)) or isinstance(right, (int, float)):
        try:
            return float(left) == float(right)
        except (TypeError, ValueError):
            return False
    return str(left).strip() == str(right).strip()


def _tier_distance(left_tier: str, right_tier: str) -> int:
    return abs(SIZE_TIER_ORDER.index(left_tier) - SIZE_TIER_ORDER.index(right_tier))


def _pick_best_preset(
    pool: List[ConsolidationPreset],
    mapped_worker: str,
    prod_num_workers: Optional[int] = None,
    size_tier: Optional[str] = None,
) -> ConsolidationPreset:
    exact = [preset for preset in pool if preset.node_type_id == mapped_worker]
    if exact:
        if prod_num_workers is not None:
            workers_match = [
                preset for preset in exact if preset.num_workers == prod_num_workers
            ]
            if workers_match:
                return workers_match[0]
        return exact[0]

    if prod_num_workers is not None:
        workers_match = [
            preset for preset in pool if preset.num_workers == prod_num_workers
        ]
        if workers_match:
            if size_tier is not None:
                workers_match.sort(
                    key=lambda preset: (
                        _tier_distance(preset.size_tier, size_tier),
                        SIZE_TIER_ORDER.index(preset.size_tier),
                    )
                )
            return workers_match[0]

    if size_tier is not None:
        pool = sorted(
            pool,
            key=lambda preset: (
                _tier_distance(preset.size_tier, size_tier),
                SIZE_TIER_ORDER.index(preset.size_tier),
            ),
        )

    return pool[0]


def _widen_by_worker_topology(
    *,
    catalog: List[ConsolidationPreset],
    family: str,
    size_tier: str,
    single_node: bool,
    mapped_worker: str,
    homogeneous: bool,
    mapped_driver: Optional[str],
) -> List[ConsolidationPreset]:
    """Expand search within family and single-/multi-node mode, still worker-first."""
    family_pool = [
        preset
        for preset in catalog
        if preset.family == family and preset.is_single_node == single_node
    ]
    if not family_pool:
        return []

    exact_worker = [
        preset for preset in family_pool if preset.node_type_id == mapped_worker
    ]
    if exact_worker:
        if homogeneous and mapped_driver is not None:
            driver_match = [
                preset
                for preset in exact_worker
                if preset.driver_node_type_id == mapped_driver
            ]
            if driver_match:
                return driver_match
        else:
            return exact_worker

    same_tier = [preset for preset in family_pool if preset.size_tier == size_tier]
    if same_tier:
        return same_tier

    tier_index = SIZE_TIER_ORDER.index(size_tier)
    for offset in (-1, 1, -2, 2, -3, 3, -4, 4):
        neighbor_index = tier_index + offset
        if neighbor_index < 0 or neighbor_index >= len(SIZE_TIER_ORDER):
            continue
        neighbor_tier = SIZE_TIER_ORDER[neighbor_index]
        neighbor_pool = [
            preset for preset in family_pool if preset.size_tier == neighbor_tier
        ]
        if neighbor_pool:
            return neighbor_pool

    return family_pool


def _alternates_excluding_prod(
    pool: List[ConsolidationPreset], prod_cluster_type: str
) -> List[ConsolidationPreset]:
    if len(pool) == 1 and pool[0].name == prod_cluster_type:
        return []
    return [preset for preset in pool if preset.name != prod_cluster_type]


def match_consolidation_preset(
    *,
    effective_prod: dict,
    prod_cluster_type: str,
    catalog: List[ConsolidationPreset],
) -> Optional[ConsolidationPreset]:
    """
    Pick a consolidation validation preset from worker topology.

    Returns None when prod already matches the sole consolidation preset (skip validation).
    """
    mapped_worker, mapped_driver = _mapped_worker_and_driver(
        effective_prod, prod_cluster_type
    )
    homogeneous = _is_homogeneous_topology(mapped_worker, mapped_driver)
    family, size_tier = _topology_from_mapped_worker(mapped_worker)
    single_node = is_single_node_cluster(effective_prod)

    prod_num_workers = effective_prod.get("num_workers")
    if prod_num_workers is not None:
        prod_num_workers = int(prod_num_workers)

    pool = _presets_matching_worker_topology(
        catalog,
        family=family,
        single_node=single_node,
        mapped_worker=mapped_worker,
        mapped_driver=mapped_driver,
        homogeneous=homogeneous,
    )

    if not pool:
        pool = _widen_by_worker_topology(
            catalog=catalog,
            family=family,
            size_tier=size_tier,
            single_node=single_node,
            mapped_worker=mapped_worker,
            homogeneous=homogeneous,
            mapped_driver=mapped_driver,
        )

    if not pool:
        raise ValueError(
            f"No consolidation validation preset for family={family!r}, "
            f"size_tier={size_tier!r}, single_node={single_node}, "
            f"mapped_worker={mapped_worker!r}, prod_type={prod_cluster_type!r}"
        )

    alternates = _alternates_excluding_prod(pool, prod_cluster_type)
    if not alternates:
        return None

    return _pick_best_preset(
        alternates,
        mapped_worker,
        prod_num_workers=prod_num_workers,
        size_tier=size_tier,
    )


def _aws_attributes_from_config(config: dict) -> Dict[str, Any]:
    attrs = config.get("aws_attributes") or {}
    if not isinstance(attrs, dict):
        return {}
    return dict(attrs)


def _compute_aws_attributes_validation_overrides(
    effective_prod: dict,
    validation_resolved: dict,
) -> Dict[str, Any]:
    """Emit aws_attributes keys where effective prod differs from validation preset defaults."""
    prod_attrs = _aws_attributes_from_config(effective_prod)
    preset_attrs = _aws_attributes_from_config(validation_resolved)
    overrides: Dict[str, Any] = {}
    for key, prod_value in prod_attrs.items():
        if prod_value is not None and not _values_equal(
            prod_value, preset_attrs.get(key)
        ):
            overrides[key] = prod_value
    return overrides


def compute_validation_overrides(
    *,
    effective_prod: dict,
    mapped_worker: str,
    mapped_driver: Optional[str],
    validation_resolved: dict,
    prod_cluster_type: str = "",
) -> Dict[str, Any]:
    """Emit only cluster fields where effective prod differs from validation defaults."""
    overrides: Dict[str, Any] = {}

    prod_spark = effective_prod.get("spark_version")
    preset_spark = validation_resolved.get("spark_version")
    if prod_spark is not None and not _values_equal(prod_spark, preset_spark):
        overrides["spark_version"] = prod_spark

    prod_workers = effective_prod.get("num_workers")
    preset_workers = validation_resolved.get("num_workers")
    if prod_workers is not None and not _values_equal(prod_workers, preset_workers):
        overrides["num_workers"] = prod_workers

    preset_worker = validation_resolved.get("node_type_id")
    preset_driver = validation_resolved.get(
        "master_node_type_id"
    ) or validation_resolved.get("driver_node_type_id")

    if not _values_equal(mapped_worker, preset_worker):
        overrides["node_type_id"] = mapped_worker
    capped_driver = cap_validation_driver_node_type(mapped_driver)
    if capped_driver and not _values_equal(capped_driver, preset_driver):
        overrides["driver_node_type_id"] = capped_driver

    if _uses_photon(effective_prod, prod_cluster_type) and not _values_equal(
        "PHOTON", validation_resolved.get("runtime_engine")
    ):
        overrides["runtime_engine"] = "PHOTON"

    aws_overrides = _compute_aws_attributes_validation_overrides(
        effective_prod, validation_resolved
    )
    if aws_overrides:
        overrides["aws_attributes"] = aws_overrides

    return overrides


def declaration_validation_spark_conf(declaration: dict) -> Dict[str, Any]:
    """Optional validation.cluster.custom_configurations.spark_conf from declaration."""
    validation = declaration.get("validation") or {}
    cluster = validation.get("cluster") or {}
    custom_configurations = cluster.get("custom_configurations") or {}
    spark_conf = custom_configurations.get("spark_conf") or {}
    if not isinstance(spark_conf, dict):
        return {}
    return dict(spark_conf)


def merge_declaration_validation_spark_conf(
    declaration: dict, custom_configurations: Dict[str, Any]
) -> Dict[str, Any]:
    """Merge declaration validation spark_conf into generated validation overrides."""
    extra_spark_conf = declaration_validation_spark_conf(declaration)
    if not extra_spark_conf:
        return custom_configurations
    merged = dict(custom_configurations)
    spark_conf = dict(merged.get("spark_conf") or {})
    spark_conf.update(extra_spark_conf)
    merged["spark_conf"] = spark_conf
    return merged


def build_validation_cluster_spec(
    *,
    cluster_args: dict,
    declaration: dict,
    config_service: Optional[ConfigurationService] = None,
    catalog: Optional[List[ConsolidationPreset]] = None,
) -> Optional[ValidationClusterSpec]:
    """Build validation.cluster spec from prod cluster args and full declaration."""
    eligibility = validation_eligibility_label(declaration)
    if eligibility is None:
        return None

    service = config_service or ConfigurationService()
    effective_prod = merge_cluster_configuration(cluster_args, service)
    if is_emr_effective_config(effective_prod):
        return None

    prod_cluster_type = cluster_args.get("type", "")
    preset_catalog = (
        catalog if catalog is not None else build_consolidation_catalog(service)
    )
    mapped_worker, mapped_driver = _mapped_worker_and_driver(
        effective_prod, prod_cluster_type
    )

    matched = match_consolidation_preset(
        effective_prod=effective_prod,
        prod_cluster_type=prod_cluster_type,
        catalog=preset_catalog,
    )
    if matched is None:
        return None

    validation_resolved = service.get_config(matched.name)

    custom_configurations = compute_validation_overrides(
        effective_prod=effective_prod,
        mapped_worker=mapped_worker,
        mapped_driver=mapped_driver,
        validation_resolved=validation_resolved,
        prod_cluster_type=prod_cluster_type,
    )

    custom_configurations = merge_declaration_validation_spark_conf(
        declaration, custom_configurations
    )

    allow_custom_spark_job = _has_load_spark_job(declaration)

    return ValidationClusterSpec(
        cluster_type=matched.name,
        custom_configurations=custom_configurations,
        databricks_conn_id=cluster_args.get("databricks_conn_id"),
        access_control_list=cluster_args.get("access_control_list"),
        custom_libraries=cluster_args.get("custom_libraries"),
        allow_custom_spark_job=allow_custom_spark_job,
    )
