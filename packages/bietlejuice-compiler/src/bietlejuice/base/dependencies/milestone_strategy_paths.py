"""Detect milestone strategy SQL paths without colliding with other nested folders.

``queries/<layer>/<table>/milestones/*.sql`` is a reserved layout:

- Under ``workflow.type: milestone_delta``, files are strategy extractors and
  attribute dependencies to the parent DAG.
- Under any other workflow, the same layout is skipped (never mis-parsed as a
  flat/len-6 query path) and never registered as standalone tables.

Other nested folder names (e.g. ``strategies/``) are unaffected — they need a
separate nested-query design when introduced.
"""

from __future__ import annotations

import re
from functools import lru_cache
from os.path import isfile, join
from typing import Match, Optional

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService

# After stripping domain: <dag>/queries/<layer>/<table>/milestones/<file>.sql
MILESTONE_STRATEGY_RELATIVE_RE = re.compile(
    r"^([^/]+)/queries/[^/]+/[^/]+/milestones/[^/]+\.sql$"
)

# Full path under dags/: .../dags/<domain>/<dag>/queries/<layer>/<table>/milestones/<file>.sql
MILESTONE_STRATEGY_FULL_RE = re.compile(
    r"/dags/[^/]+/([^/]+)/queries/[^/]+/[^/]+/milestones/[^/]+\.sql$"
)


def match_milestone_strategy_relative(relative_path: str) -> Optional[Match[str]]:
    """Match a domain-stripped relative path as a milestone strategy file."""
    return MILESTONE_STRATEGY_RELATIVE_RE.search(relative_path.replace("\\", "/"))


def dag_folder_from_milestone_strategy_path(file_path: str) -> Optional[str]:
    """Return DAG folder name if ``file_path`` matches the strategy layout."""
    normalized = file_path.replace("\\", "/")
    full = MILESTONE_STRATEGY_FULL_RE.search(normalized)
    if full:
        return full.group(1)
    relative = match_milestone_strategy_relative(normalized)
    if relative:
        return relative.group(1)
    return None


@lru_cache(maxsize=None)
def is_milestone_delta_dag(dag_folder: str) -> bool:
    """True when ``{dag_folder}_declaration.yml`` has workflow.type milestone_delta."""
    dag_path = DAGPackagesPathService.get_dag_path(dag_folder)
    if not dag_path:
        return False
    declaration_path = join(dag_path, f"{dag_folder}_declaration.yml")
    if not isfile(declaration_path):
        return False
    try:
        declaration = FileService.get_dict_from_yaml_file(declaration_path)
    except Exception:
        return False
    workflow = declaration.get("workflow") or {}
    return workflow.get("type") == "milestone_delta"


def is_milestone_strategy_sql(file_path: str) -> bool:
    """True only for strategy extractors under a milestone_delta DAG."""
    dag_folder = dag_folder_from_milestone_strategy_path(file_path)
    if not dag_folder:
        return False
    return is_milestone_delta_dag(dag_folder)


def is_milestone_strategy_layout(file_path: str) -> bool:
    """True when path matches strategy layout (workflow type not checked)."""
    return dag_folder_from_milestone_strategy_path(file_path) is not None


def is_milestone_strategy_dir(dir_path: str) -> bool:
    """True when ``dir_path`` is ``.../queries/<layer>/<table>/milestones``.

    Layout-only: used to avoid writing ``.table_manifest`` for the reserved
    strategy folder name. Other nested folder names are unaffected.
    """
    normalized = dir_path.replace("\\", "/").rstrip("/")
    if not normalized.endswith("/milestones"):
        return False
    return is_milestone_strategy_layout(f"{normalized}/_probe.sql")


def clear_milestone_delta_dag_cache() -> None:
    """Test helper: drop cached declaration lookups."""
    is_milestone_delta_dag.cache_clear()
