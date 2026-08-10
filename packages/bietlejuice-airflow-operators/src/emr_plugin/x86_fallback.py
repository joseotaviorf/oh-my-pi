"""TEMPORARY: force EMR clusters off Graviton (ARM) onto x86 instance types.

Graviton types are declared in two places — the ``emr_7_12_*`` presets in
``bietlejuice-core``'s ``{env}_conf.yml`` and the per-DAG
``custom_configurations`` in ``dags/**/*_cluster.yml``, which deep-merge *over*
the preset. Rewriting either in place would mean touching ~500 files and
relaxing the CI audit in ``audit_cluster_instance_families.py`` (it mandates a
6g worker family for ``emr_7_12_*`` presets). Instead this module remaps at the
single runtime choke point: :func:`emr_plugin.template_translator.translate`,
which every EMR cluster passes through — production and cluster-validation,
instance groups and instance fleets alike.

Every mapped pair is 1:1 on vCPU and memory for the same size suffix, so the
presets' ``spark_conf`` driver/executor memory stays valid.

Escape hatches, in order of blast radius:

- ``EMR_X86_FALLBACK=0`` in the Airflow environment disables the remap globally
  without a deploy (read per call, so it takes effect on the next task).
- ``emr_allow_graviton: true`` in a cluster's ``custom_configurations`` keeps
  that one cluster on Graviton.

To revert: delete this module, its test, and the ``apply_x86_fallback(cfg)``
call in ``template_translator.translate``.
"""

from __future__ import annotations

import logging
import os
import re
from typing import Any, Dict, List

log = logging.getLogger(__name__)

X86_FALLBACK_ENV_VAR = "EMR_X86_FALLBACK"
GRAVITON_ALLOW_KEY = "emr_allow_graviton"

_DISABLED_ENV_VALUES = frozenset({"", "0", "false", "no", "off"})

# ``<class><generation><variant>.<size>``, e.g. ``r7gd.2xlarge``.
_GRAVITON_RE = re.compile(r"^([a-z]+)(\d+)(gd|g)\.(.+)$")

# Graviton family prefix -> x86 replacement, size suffix preserved.
# Non-NVMe Graviton maps to the AMD family of the same generation. AMD has no
# gen-6/7 local-NVMe family, so ``gd`` types fall back to the gen-6 Intel ``id``
# family to keep instance storage; gen-7 ``gd`` collapses onto gen-6 ``id`` for
# the same reason (there is no ``m7id``/``r7id``).
GRAVITON_TO_X86 = {
    "m6g": "m6a",
    "m7g": "m7a",
    "r6g": "r6a",
    "r7g": "r7a",
    "c6g": "c6a",
    "c7g": "c7a",
    "m6gd": "m6id",
    "m7gd": "m6id",
    "r6gd": "r6id",
    "r7gd": "r6id",
    "c6gd": "c6id",
    "c7gd": "c6id",
}

# Scalar keys read by the translator's group and fleet code paths.
_SCALAR_KEYS = (
    "master_node_type_id",
    "driver_node_type_id",
    "node_type_id",
    "task_node_type_id",
)
_NODE_BLOCK_KEYS = ("core_nodes", "task_nodes")


def x86_fallback_enabled() -> bool:
    """False when ``EMR_X86_FALLBACK`` is set to a falsy value."""
    value = os.environ.get(X86_FALLBACK_ENV_VAR, "1").strip().lower()
    return value not in _DISABLED_ENV_VALUES


def to_x86_instance_type(instance_type: Any) -> Any:
    """Map one Graviton instance type to its x86 equivalent, size preserved.

    Non-Graviton types (and non-strings) are returned untouched, which makes
    this idempotent — ``translate`` runs at both DAG-parse and task-execute
    time on the same cluster configuration.
    """
    if not isinstance(instance_type, str):
        return instance_type
    match = _GRAVITON_RE.match(instance_type.strip().lower())
    if not match:
        return instance_type
    instance_class, generation, variant, size = match.groups()
    replacement = GRAVITON_TO_X86.get(f"{instance_class}{generation}{variant}")
    if not replacement:
        return instance_type
    return f"{replacement}.{size}"


def _deduplicate(instance_types: List[Any]) -> List[Any]:
    """Drop duplicates created by the mapping, preserving order.

    ``[m6gd.4xlarge, m7gd.4xlarge]`` both resolve to ``m6id.4xlarge``; EMR
    rejects a fleet that lists the same instance type twice.
    """
    unique: List[Any] = []
    for instance_type in instance_types:
        if instance_type not in unique:
            unique.append(instance_type)
    return unique


def apply_x86_fallback(cfg: Dict[str, Any]) -> None:
    """Rewrite every Graviton instance type in a cluster config, in place."""
    allow_graviton = bool(cfg.pop(GRAVITON_ALLOW_KEY, False))
    if allow_graviton or not x86_fallback_enabled():
        return

    remapped: Dict[str, str] = {}

    def _remap(value: Any) -> Any:
        mapped = to_x86_instance_type(value)
        if isinstance(value, str) and mapped != value:
            remapped[value] = mapped
        return mapped

    for key in _SCALAR_KEYS:
        if cfg.get(key) is not None:
            cfg[key] = _remap(cfg[key])

    for block_key in _NODE_BLOCK_KEYS:
        block = cfg.get(block_key)
        if not isinstance(block, dict):
            continue
        if block.get("node_type_id") is not None:
            block["node_type_id"] = _remap(block["node_type_id"])
        instance_types = block.get("instance_types")
        if isinstance(instance_types, list):
            block["instance_types"] = _deduplicate(
                [_remap(instance_type) for instance_type in instance_types]
            )

    if remapped:
        log.info(
            "EMR x86 fallback active: remapped Graviton instance types %s. "
            "Set %s=0 to disable globally, or emr_allow_graviton: true on the "
            "cluster to opt out.",
            ", ".join(f"{source} -> {target}" for source, target in remapped.items()),
            X86_FALLBACK_ENV_VAR,
        )
