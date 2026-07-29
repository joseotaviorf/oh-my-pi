"""Resolve which DataHub platforms a table's metadata should be propagated to.

Single source of truth for the "table -> platforms" mapping consumed by the
metadata-propagator payload (the ``platforms`` field). It mirrors how table
availability is actually controlled in the DAG declaration:

- **databricks + glue**: always present for physical tables (the table is Delta
  on Databricks, and the Unity Catalog <-> AWS Glue metadata sync keeps the Glue
  Data Catalog populated).
- **trino**: only when the table is Hive-synced.
    - Normal workflows: ``has_hive_sync`` resolved as
      ``table_customization -> workflow default -> per-type default``. The
      per-type default is ``False`` for ``core_model`` and ``True`` otherwise.
    - ``query_view`` workflows: ``has_hive_sync`` is not accepted; availability
      comes from ``sync`` / ``sql_dialect`` (see
      :mod:`bietlejuice.base.pipeline.query_view_sync`). Such views live on the
      platforms named in ``sync`` (a subset of ``databricks``/``trino``) and are
      **not** Glue-synced.
Platform membership is a property of the FQN (schema.table) alone -- the same
set is used for descriptions, data quality and any other per-table metadata.
Whether a run is a validation run is intentionally NOT a factor here: isolating
validation from prod is handled by the target environment/host (forno vs prod),
not by dropping platforms.

Cascade evidence (do not duplicate, keep in sync):
``base_workflow._check_include_sync_hive_tasks`` (default ``True``);
``core_model_workflow._check_include_sync_hive_tasks`` (default ``False``
override); ``query_view_workflow`` via ``normalize_query_view_sync_config``.
"""

from __future__ import annotations

from enum import Enum
from typing import Any, Dict, List, Optional

from bietlejuice.base.pipeline.query_view_sync import normalize_query_view_sync_config


class DataHubPlatform(str, Enum):
    """DataHub data platforms a bietlejuice table can be propagated to."""

    DATABRICKS = "databricks"
    GLUE = "glue"
    TRINO = "trino"


# ``WorkflowEnum`` values mirrored here so this module stays free of any
# airflow/dag-builder import (base.pipeline must not depend on base.airflow).
_CORE_MODEL_WORKFLOW = "core_model"
_QUERY_VIEW_WORKFLOW = "query_view"

# Physical tables always land on Databricks (Delta) and Glue (UC <-> Glue sync).
_ALWAYS_TABLE_PLATFORMS = (
    DataHubPlatform.DATABRICKS.value,
    DataHubPlatform.GLUE.value,
)


def resolve_has_hive_sync(
    workflow_type: str,
    workflow_args: Dict[str, Any],
    table_customization: Optional[Dict[str, Any]] = None,
) -> bool:
    """Resolve ``has_hive_sync`` for a non-``query_view`` table (Trino availability).

    Cascade: ``table_customization["has_hive_sync"]`` overrides
    ``workflow_args["has_hive_sync"]`` overrides the per-type default
    (``False`` for ``core_model``, ``True`` otherwise).

    Reflects the table's declared platform footprint only -- not gated by
    ``is_validation`` (that concerns a run's task graph, not where the table
    lives).
    """
    table_customization = table_customization or {}
    type_default = workflow_type != _CORE_MODEL_WORKFLOW  # True unless core_model
    workflow_level = workflow_args.get("has_hive_sync", type_default)
    return bool(table_customization.get("has_hive_sync", workflow_level))


def resolve_platforms(
    workflow_type: str,
    workflow_args: Dict[str, Any],
    table_customization: Optional[Dict[str, Any]] = None,
) -> List[str]:
    """Return the DataHub platforms a table's metadata should be propagated to.

    Purely a property of the FQN (schema.table), from the DAG declaration -- the
    same set used for descriptions, data quality and any other per-table
    metadata. Not affected by whether the current run is a validation run:
    validation vs prod is handled by the target environment/host, not here.
    """
    table_customization = table_customization or {}

    if workflow_type == _QUERY_VIEW_WORKFLOW:
        # Views: presence is governed strictly by ``sync`` (databricks/trino),
        # not by the always-on databricks+glue table rule.
        return list(
            normalize_query_view_sync_config(workflow_args, table_customization).sync
        )

    platforms = list(_ALWAYS_TABLE_PLATFORMS)
    if resolve_has_hive_sync(workflow_type, workflow_args, table_customization):
        platforms.append(DataHubPlatform.TRINO.value)
    return platforms
