"""Throwaway DAGs for the datalake layer taxonomy pilot, and their exclusions.

These four DAGs exist only to exercise the new ``transformation`` and
``consumption`` layers end to end (see ``LayerEnum``). They are duplicates of the
offboarding vertical slice writing to ``*_test`` schemas, are manual-trigger
only, and are deleted once the pilot concludes.

Governance checks that assume a DAG is a real, permanent, owned pipeline are
skipped for them. Existing exclusions key on the path prefix
``dags/platform/migration_``, which does not reach these DAGs because they live
in a domain folder. An explicit set of names is used rather than a ``_test``
suffix match so the hole closes when the folders are deleted, instead of
silently applying to unrelated future DAGs.

What is **not** skipped, deliberately: source-layer policy, metadata validation,
lineage consistency, FAIR metadata, Databricks SQL constructs, join-shape lint,
and the no-new-Databricks-clusters check. Making source-layer policy evaluate
the ``consumption <- transformation`` edge is the point of the pilot, so
excluding it would defeat the exercise. The pilot ships metadata for every
table it writes, so the metadata validators are the only thing exercising the
``transformation`` database-name formula and Yamale routing against real files.
The EMR-compatibility lints stay on because the pilot runs on EMR clusters;
the cluster check stays on because the DAGs already declare EMR YAML and have
no hand-written Python, so the exclusion covered nothing.

Teardown: delete the four folders, then delete this module and its imports.
"""

from __future__ import annotations

PILOT_DAG_DOMAIN = "governance"

PILOT_DAG_NAMES = frozenset(
    {
        "transformation_terminator_test",
        "transformation_offboarding_test",
        "transformation_hefesto_test",
        "consumption_offboarding_test",
    }
)

# Repo-relative folder prefixes, e.g. "dags/governance/consumption_offboarding_test/".
# Trailing slash prevents a longer sibling name from matching by prefix.
PILOT_DAG_PATH_PREFIXES = tuple(
    f"dags/{PILOT_DAG_DOMAIN}/{name}/" for name in sorted(PILOT_DAG_NAMES)
)


def is_pilot_dag(dag_name: str) -> bool:
    """True when ``dag_name`` is one of the pilot DAGs."""
    return dag_name in PILOT_DAG_NAMES


def is_pilot_dag_path(repo_relative_path: str) -> bool:
    """True when a repo-relative path lives inside a pilot DAG folder."""
    return repo_relative_path.startswith(PILOT_DAG_PATH_PREFIXES)
