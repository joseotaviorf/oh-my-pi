from __future__ import annotations

import os

from bietlejuice.base.paths import DAG_PACKAGES_ROOT
from bietlejuice.governance.layer_taxonomy_pilot import (
    PILOT_DAG_DOMAIN,
    PILOT_DAG_NAMES,
)

_DAG_ID_PREFIX = "bietlejuice."
# Luigi Jr DAGs live under dags/luigijr/. They are scaffolded by Zordon and
# deployed only to dedicated luigijr Astro instances (forno-luigijr / prod
# luigijr), isolated from the main forno/prod DAG bag. Their bot-authored PRs
# only touch dags/luigijr/** and never update the shared dags/dependencies.yaml,
# and they are scheduled independently on their own instance rather than being
# dataset-triggered from upstream DAGs. So the shared dependency file is not
# expected to track them: skip DAGs keyed under this domain when checking
# correctness. Mirrors the path-prefix exception used by
# validate_no_new_databricks_clusters (databricks_cluster_exceptions.yml).
_LUIGIJR_DOMAIN_DIR = "luigijr"
_MIGRATION_DAG_PREFIXES = ("migration_twin_", "migration_emr_", "migration_compare_")


def ignored_dag_ids(dags_root: str | None = None) -> frozenset[str]:
    """Return dependency-file keys to skip: luigijr, emr-migration-v2 and taxonomy pilot DAGs."""
    if dags_root is None:
        dags_root = DAG_PACKAGES_ROOT
    ids: set[str] = set()
    luigijr_dir = os.path.join(dags_root, _LUIGIJR_DOMAIN_DIR)
    if os.path.isdir(luigijr_dir):
        ids.update(
            f"{_DAG_ID_PREFIX}{name}"
            for name in os.listdir(luigijr_dir)
            if os.path.isdir(os.path.join(luigijr_dir, name))
        )
    platform_dir = os.path.join(dags_root, "platform")
    if os.path.isdir(platform_dir):
        ids.update(
            f"{_DAG_ID_PREFIX}{name}"
            for name in os.listdir(platform_dir)
            if os.path.isdir(os.path.join(platform_dir, name))
            and name.startswith(_MIGRATION_DAG_PREFIXES)
        )
    pilot_dir = os.path.join(dags_root, PILOT_DAG_DOMAIN)
    if os.path.isdir(pilot_dir):
        ids.update(
            f"{_DAG_ID_PREFIX}{name}"
            for name in os.listdir(pilot_dir)
            if os.path.isdir(os.path.join(pilot_dir, name)) and name in PILOT_DAG_NAMES
        )
    return frozenset(ids)


def filter_ignored_dag_dependencies(dependencies: dict) -> dict:
    """Drop DAG keys that are not tracked in the shared dependencies.yaml."""
    ignored = ignored_dag_ids()
    return {dag: deps for dag, deps in dependencies.items() if dag not in ignored}
