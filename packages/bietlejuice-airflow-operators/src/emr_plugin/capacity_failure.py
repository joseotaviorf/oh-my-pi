from __future__ import annotations

import logging
import re
from typing import Any, List, Optional

import botocore.exceptions

from emr_plugin.instance_alternates import first_x86

log = logging.getLogger(__name__)

CAPACITY_REASON_CODES = frozenset(
    {"INTERNAL_ERROR", "VALIDATION_ERROR", "INSTANCE_FAILURE", "INSTANCE_FLEET_TIMEOUT"}
)
CAPACITY_MESSAGE_PATTERN = re.compile(
    r"exceeds the EC2 service quota|insufficient\s+(?:instance\s+)?capacity"
    r"|InsufficientInstanceCapacity",
    re.IGNORECASE,
)

_SCALAR_KEYS = (
    "master_node_type_id",
    "driver_node_type_id",
    "node_type_id",
    "task_node_type_id",
)
_NODE_BLOCK_KEYS = ("core_nodes", "task_nodes")


def classify_launch_failure(
    emr_client: Any, cluster_id: Optional[str]
) -> Optional[str]:
    """Classify whether a cluster termination was due to EC2 capacity or quota limits.

    Calls describe_cluster(ClusterId=cluster_id), reads
    Cluster.Status.StateChangeReason.{Code,Message}, and returns the message when
    Code is in CAPACITY_REASON_CODES and Message matches CAPACITY_MESSAGE_PATTERN;
    otherwise returns None.
    Swallows botocore.exceptions.ClientError and returns None.
    """
    if not emr_client or not cluster_id:
        return None
    try:
        response = emr_client.describe_cluster(ClusterId=cluster_id)
        cluster = response.get("Cluster", {})
        status = cluster.get("Status", {})
        state_change_reason = status.get("StateChangeReason", {})
        code = state_change_reason.get("Code")
        message = state_change_reason.get("Message", "")
        if (
            code in CAPACITY_REASON_CODES
            and message
            and CAPACITY_MESSAGE_PATTERN.search(message)
        ):
            return message
    except botocore.exceptions.ClientError as e:
        log.warning(
            "ClientError describing EMR cluster %s for capacity failure diagnosis: %s",
            cluster_id,
            e,
        )
    except Exception as e:
        log.warning(
            "Unexpected error describing EMR cluster %s for capacity failure diagnosis: %s",
            cluster_id,
            e,
        )
    return None


def _deduplicate(instance_types: List[Any]) -> List[Any]:
    unique: List[Any] = []
    for instance_type in instance_types:
        if instance_type not in unique:
            unique.append(instance_type)
    return unique


def force_x86(cfg: dict) -> dict[str, str]:
    """Rewrite, in place, Graviton instance types to their first x86 alternate.

    Rewrites master_node_type_id, driver_node_type_id, node_type_id,
    task_node_type_id, and node_type_id / instance_types inside core_nodes
    and task_nodes using first_x86(...) from instance_alternates.

    Leaves a type with no x86 sibling untouched, de-duplicates resulting lists,
    and returns the {original: replacement} map for logging and alert text.
    """
    remapped: dict[str, str] = {}

    def _remap(value: Any) -> Any:
        if not isinstance(value, str):
            return value
        replacement = first_x86(value)
        if replacement and replacement != value:
            remapped[value] = replacement
            return replacement
        return value

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

    return remapped
