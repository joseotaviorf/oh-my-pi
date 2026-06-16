#!/usr/bin/env python3
"""
Audit *_cluster.yml topology overrides against preset defaults and consolidation families.

Fails when:
- custom_configurations restate preset-default topology (redundant echoes)
- *_single_node_cluster presets set num_workers > 0
- overrides change instance generation/variant or instance category vs presets
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, List, Optional, Tuple

import yaml

_COMPILER_ROOT = Path(__file__).resolve().parents[2]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))

REPO_ROOT = Path(__file__).resolve().parents[4]

from bietlejuice.base.airflow.cluster_config_resolver import merge_cluster_configuration
from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    _instance_family,
    find_redundant_preset_default_overrides,
    is_emr_effective_config,
)

INSTANCE_TYPE_RE = re.compile(r"^([mrc])(\d+)([a-z]*)\.(.+)$", re.IGNORECASE)

# Spark-relevant topology keys in custom_configurations (flat and nested).
WORKER_TOPOLOGY_PATHS = (
    ("node_type_id",),
    ("task_node_type_id",),
    ("core_nodes", "node_type_id"),
    ("task_nodes", "node_type_id"),
)
DRIVER_TOPOLOGY_PATHS = (("driver_node_type_id",),)
MASTER_TOPOLOGY_PATHS = (("master_node_type_id",),)

DATABRICKS_CONSOLIDATION_PREFIX = "consolidation_"
EMR_CONSOLIDATION_PREFIX = "emr_7_12_consolidation_"
EMR_LEGACY_MIN_PREFIX = "emr_7_12_min_"

EXPECTED_GENERATION = {
    "databricks_consolidation": 7,
    "emr_consolidation": 7,
    "emr_legacy_min": 7,
}


@dataclass(frozen=True)
class Violation:
    dag: str
    cluster_path: str
    preset_type: str
    topology_key: str
    preset_default: str
    override_value: str
    reason: str

    def format_line(self) -> str:
        return (
            f"{self.dag}\t{self.topology_key}\t"
            f"preset={self.preset_default}\toverride={self.override_value}\t"
            f"{self.reason}"
        )


def _parse_instance_type(instance_type: str) -> Tuple[str, int, str, str]:
    match = INSTANCE_TYPE_RE.match(str(instance_type).strip().lower())
    if not match:
        raise ValueError(f"Unrecognized instance type: {instance_type!r}")
    return match.group(1), int(match.group(2)), match.group(3), match.group(4)


def generation_variant_key(instance_type: str) -> str:
    """Normalized generation+variant for preset/override comparison (6gd == 6g, 7gd == 7g)."""
    _class, generation, variant, _size = _parse_instance_type(instance_type)
    if generation == 6 and variant in ("gd", "g"):
        return "6g"
    if generation == 7 and variant in ("gd", "g"):
        return "7g"
    return f"{generation}{variant}"


def is_graviton_6g_family(instance_type: str) -> bool:
    _class, generation, variant, _size = _parse_instance_type(instance_type)
    # Require explicit g/gd variant; bare m6.* is Intel/AMD gen-6, not Graviton m6g.
    return generation == 6 and variant in ("g", "gd")


def is_graviton_7g_family(instance_type: str) -> bool:
    _class, generation, variant, _size = _parse_instance_type(instance_type)
    return generation == 7 and variant in ("g", "gd")


def is_emr_7g_family(instance_type: str) -> bool:
    _class, generation, variant, _size = _parse_instance_type(instance_type)
    return generation == 7 and variant == "g"


def is_emr_7a_family(instance_type: str) -> bool:
    _class, generation, variant, _size = _parse_instance_type(instance_type)
    return generation == 7 and variant == "a"


def _get_nested(config: dict, path: Tuple[str, ...]) -> Optional[Any]:
    current: Any = config
    for key in path:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def _preset_default_for_path(
    preset_merged: dict, path: Tuple[str, ...]
) -> Optional[str]:
    value = _get_nested(preset_merged, path)
    if value is not None:
        return str(value) if isinstance(value, str) else None
    if path == ("node_type_id",):
        core = preset_merged.get("core_nodes") or {}
        if isinstance(core, dict) and core.get("node_type_id"):
            return str(core["node_type_id"])
    return None


def _iter_topology_overrides(
    custom: dict,
) -> Iterator[Tuple[str, Tuple[str, ...], str]]:
    if not isinstance(custom, dict):
        return
    for label, path in (
        *[(f"driver:{p[-1]}", p) for p in DRIVER_TOPOLOGY_PATHS],
        *[(f"worker:{p[-1]}", p) for p in WORKER_TOPOLOGY_PATHS],
        *[(f"master:{p[-1]}", p) for p in MASTER_TOPOLOGY_PATHS],
    ):
        value = _get_nested(custom, path)
        if value is not None and isinstance(value, str):
            yield label, path, value


def _preset_policy(cluster_type: str) -> Optional[str]:
    if cluster_type.startswith(DATABRICKS_CONSOLIDATION_PREFIX):
        return "databricks_consolidation"
    if cluster_type.startswith(EMR_CONSOLIDATION_PREFIX):
        return "emr_consolidation"
    if cluster_type.startswith(EMR_LEGACY_MIN_PREFIX):
        return "emr_legacy_min"
    return None


def _check_consolidation_family(
    cluster_type: str, instance_type: str, topology_label: str
) -> Optional[str]:
    policy = _preset_policy(cluster_type)
    if policy == "databricks_consolidation":
        if topology_label.startswith("master:"):
            return None
        if not is_graviton_7g_family(instance_type):
            return "databricks_consolidation_requires_7g_family"
    if policy == "emr_consolidation":
        if topology_label.startswith("master:"):
            return None
        if not is_emr_7g_family(instance_type):
            return "emr_consolidation_requires_7g_family"
    if policy == "emr_legacy_min":
        if not is_emr_7a_family(instance_type) and not is_emr_7g_family(instance_type):
            return "emr_legacy_min_requires_7a_or_7g_family"
        return None
    return None


def _emr_legacy_min_allows_explicit_override(cluster_type: str) -> bool:
    """emr_7_12_min_* presets allow explicit 7a/7g sizing overrides (not preset-default drift)."""
    return cluster_type.startswith(EMR_LEGACY_MIN_PREFIX)


def _databricks_override_requires_graviton_g(
    cluster_type: str, effective_preset: dict, topology_label: str
) -> bool:
    if _preset_policy(cluster_type) == "databricks_consolidation":
        return True
    if is_emr_effective_config(effective_preset):
        return False
    if cluster_type.startswith("databricks_"):
        return True
    return cluster_type in ("custom_cluster", "custom_cluster_with_sedona")


def _allows_legacy_to_graviton_migration(
    cluster_type: str, override_value: str
) -> bool:
    """Legacy presets (custom_cluster, databricks_*) may use 6g after extract normalization."""
    if not is_graviton_6g_family(override_value):
        return False
    if cluster_type in ("custom_cluster", "custom_cluster_with_sedona"):
        return True
    if cluster_type.startswith("databricks_") and not cluster_type.startswith(
        "consolidation_"
    ):
        return True
    return False


def _compare_override_to_preset(
    cluster_type: str,
    topology_label: str,
    preset_default: str,
    override_value: str,
    effective_preset: dict,
) -> Optional[str]:
    if _emr_legacy_min_allows_explicit_override(cluster_type):
        if not is_emr_7a_family(override_value) and not is_emr_7g_family(
            override_value
        ):
            return "emr_legacy_override_must_be_7a_or_7g"
        return _check_consolidation_family(cluster_type, override_value, topology_label)

    try:
        preset_gv = generation_variant_key(preset_default)
        override_gv = generation_variant_key(override_value)
    except ValueError:
        return "unrecognized_instance_type"

    graviton_migration = _allows_legacy_to_graviton_migration(
        cluster_type, override_value
    )

    if preset_gv != override_gv:
        if graviton_migration:
            pass
        else:
            return "generation_variant_mismatch"

    try:
        preset_cat = _instance_family(preset_default)
        override_cat = _instance_family(override_value)
    except ValueError:
        return "unrecognized_instance_family"

    if (
        topology_label.startswith("worker:")
        and preset_cat != override_cat
        and not graviton_migration
    ):
        return "worker_instance_category_mismatch"

    if _databricks_override_requires_graviton_g(
        cluster_type, effective_preset, topology_label
    ) and not topology_label.startswith("master:"):
        if _preset_policy(cluster_type) == "databricks_consolidation":
            if not is_graviton_7g_family(override_value):
                return "databricks_requires_7g_family"
        elif not is_graviton_6g_family(override_value):
            return "databricks_requires_6g_family"

    return _check_consolidation_family(cluster_type, override_value, topology_label)


def _format_topology_value(value: Any) -> str:
    return str(value)


def _audit_cluster_block(
    cluster: dict,
    *,
    path_label: str,
    dag_name: str,
    config_service: ConfigurationService,
) -> List[Violation]:
    cluster_type = cluster.get("type")
    if not cluster_type:
        return []

    custom = cluster.get("custom_configurations") or {}
    preset_merged = merge_cluster_configuration({"type": cluster_type}, config_service)
    violations: List[Violation] = []

    if str(cluster_type).endswith("_single_node_cluster"):
        num_workers = custom.get("num_workers")
        if num_workers is not None and int(num_workers) > 0:
            violations.append(
                Violation(
                    dag=dag_name,
                    cluster_path=path_label,
                    preset_type=str(cluster_type),
                    topology_key="num_workers",
                    preset_default="0",
                    override_value=str(num_workers),
                    reason="single_node_cluster_with_workers",
                )
            )

    redundant_items = find_redundant_preset_default_overrides(cluster, config_service)
    for item in redundant_items:
        violations.append(
            Violation(
                dag=dag_name,
                cluster_path=path_label,
                preset_type=str(cluster_type),
                topology_key=".".join(item.path),
                preset_default=_format_topology_value(item.preset_default),
                override_value=_format_topology_value(item.override_value),
                reason="redundant_preset_default_override",
            )
        )

    redundant_paths = {item.path for item in redundant_items}

    for topology_label, path, override_value in _iter_topology_overrides(custom):
        if path in redundant_paths:
            continue

        preset_default = _preset_default_for_path(preset_merged, path)
        if preset_default is None or not isinstance(preset_default, str):
            reason = _check_consolidation_family(
                cluster_type, override_value, topology_label
            )
            if not reason and _databricks_override_requires_graviton_g(
                cluster_type, preset_merged, topology_label
            ):
                if not topology_label.startswith("master:"):
                    if _preset_policy(cluster_type) == "databricks_consolidation":
                        if not is_graviton_7g_family(override_value):
                            reason = "databricks_requires_7g_family"
                    elif not is_graviton_6g_family(override_value):
                        reason = "databricks_requires_6g_family"
            if reason:
                violations.append(
                    Violation(
                        dag=dag_name,
                        cluster_path=path_label,
                        preset_type=str(cluster_type),
                        topology_key=".".join(path),
                        preset_default="(preset unset)",
                        override_value=override_value,
                        reason=reason,
                    )
                )
            continue

        if str(preset_default).lower() == str(override_value).lower():
            continue

        reason = _compare_override_to_preset(
            cluster_type,
            topology_label,
            preset_default,
            override_value,
            preset_merged,
        )
        if reason:
            violations.append(
                Violation(
                    dag=dag_name,
                    cluster_path=path_label,
                    preset_type=str(cluster_type),
                    topology_key=".".join(path),
                    preset_default=preset_default,
                    override_value=override_value,
                    reason=reason,
                )
            )
    return violations


def _cluster_path_label(cluster_path: Path) -> str:
    try:
        return cluster_path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return cluster_path.as_posix()


def audit_cluster_file(
    cluster_path: Path,
    config_service: ConfigurationService,
) -> List[Violation]:
    document = yaml.safe_load(cluster_path.read_text(encoding="utf-8")) or {}
    dag_name = cluster_path.parent.name
    path_label = _cluster_path_label(cluster_path)

    violations: List[Violation] = []
    cluster = document.get("cluster") or {}
    if cluster.get("type"):
        violations.extend(
            _audit_cluster_block(
                cluster,
                path_label=path_label,
                dag_name=dag_name,
                config_service=config_service,
            )
        )

    validation = document.get("validation") or {}
    validation_cluster = validation.get("cluster") or {}
    if validation_cluster.get("type"):
        violations.extend(
            _audit_cluster_block(
                validation_cluster,
                path_label=f"{path_label}#validation",
                dag_name=dag_name,
                config_service=config_service,
            )
        )

    return violations


def audit_tree(root: Path, config_service: ConfigurationService) -> List[Violation]:
    violations: List[Violation] = []
    for cluster_path in sorted(root.rglob("*_cluster.yml")):
        violations.extend(audit_cluster_file(cluster_path, config_service))
    return violations


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "path",
        nargs="?",
        default="dags/",
        help="DAG subtree to scan (default: dags/)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit 1 when violations are found (CI mode)",
    )
    args = parser.parse_args(argv)

    os.environ.setdefault("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()

    scan_root = REPO_ROOT / args.path
    config_service = ConfigurationService()
    violations = audit_tree(scan_root, config_service)

    if not violations:
        print("No cluster topology audit violations found.")
        return 0

    print(f"Found {len(violations)} cluster topology audit violation(s):\n")
    for violation in violations:
        print(violation.format_line())

    return 1 if args.check else 0


if __name__ == "__main__":
    sys.exit(main())
