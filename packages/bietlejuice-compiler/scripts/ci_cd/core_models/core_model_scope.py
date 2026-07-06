#!/usr/bin/env python3
"""Shared scope resolver for the core-model CI step.

Given the files changed in a branch (relative to the diff base returned by
``resolve_diff_from_ref``), decide:

* whether the whole core-model suite must run (a shared/base change), or
* which individual model subtrees are impacted (a per-model change), and
* the matching pytest test paths + coverage source paths.

Both ``check_core_model_changes.py`` (gate: are there any changes?) and
``check_core_model_coverage.py`` (run scoped tests + diff-cover gate) import this
module so the path rules live in exactly one place.

Isolated to the core-model CI step: imported only by the two sibling scripts in
this directory; nothing else in the repo references it.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Tuple

# scripts/ root on sys.path so ``services.git_service`` resolves the same way the
# sibling scripts do.
sys.path.append(str(Path(__file__).parent.parent.parent))
from services.git_service import GitService  # noqa: E402

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref  # noqa: E402

# .../scripts/ci_cd/core_models/core_model_scope.py -> repo root is parents[5]
REPO_ROOT = Path(__file__).resolve().parents[5]

# --- Full-suite triggers ------------------------------------------------------
# Any changed file under one of these prefixes forces the entire core-model suite
# (shared code / shared tests / the CI scripts themselves). Keep in sync with
# ``&core_model_tests_path`` in ``.woodpecker/tests.yml`` and with
# ``CORE_MODEL_PATHS`` in ``check_core_model_changes.py`` (historical name).
FULL_SUITE_PREFIXES: Tuple[str, ...] = (
    "packages/bietlejuice-runtime/src/bietlejuice/base/core_models/",
    "packages/bietlejuice-airflow/src/bietlejuice/base/core_models/",
    "packages/bietlejuice-core/src/bietlejuice/base/core_models/",
    "packages/bietlejuice-runtime/test/unit/base/core_models/",
    "packages/bietlejuice-compiler/scripts/ci_cd/core_models/",
)

# --- Per-model triggers -------------------------------------------------------
# ``<prefix><model>/...`` -> model ``<model>``.
MODEL_SOURCE_PREFIX = "dags/core/"
# Whole core-model test tree — parity with ``&core_model_tests_path`` in
# ``.woodpecker/tests.yml`` and the historical checker. Files under this tree but
# OUTSIDE ``unit/core/<model>/`` (e.g. the shared ``conftest.py``) are relevant
# but cannot be mapped to a single model, so they force the full suite (see
# ``resolve_scope``). ``MODEL_TEST_PREFIX`` is the narrower per-model subtree used
# to extract the model name.
MODEL_TEST_TREE = "packages/bietlejuice-runtime/test/core_model_dags/"
MODEL_TEST_PREFIX = MODEL_TEST_TREE + "unit/core/"

# --- Full-suite fallback paths (today's hardcoded behavior) -------------------
FULL_TEST_PATHS: List[str] = [
    "packages/bietlejuice-runtime/test/core_model_dags/",
    "packages/bietlejuice-runtime/test/unit/base/core_models/helpers/",
]
FULL_SOURCE_PATHS: List[str] = [
    "dags/core",
    "packages/bietlejuice-runtime/src/bietlejuice/base/core_models",
]


def _model_test_path(model: str) -> str:
    return f"{MODEL_TEST_PREFIX}{model}/"


def _model_source_path(model: str) -> str:
    return f"{MODEL_SOURCE_PREFIX}{model}"


def _model_test_dir_exists(model: str) -> bool:
    return (REPO_ROOT / _model_test_path(model)).is_dir()


@dataclass
class Scope:
    run_full: bool
    test_paths: List[str]
    cov_sources: List[str]
    models: List[str] = field(default_factory=list)
    changed_files: List[Tuple[str, str]] = field(default_factory=list)
    fallback_reason: str = ""


def _extract_model(path: str) -> Optional[str]:
    for prefix in (MODEL_SOURCE_PREFIX, MODEL_TEST_PREFIX):
        if path.startswith(prefix):
            rest = path[len(prefix) :]
            first = rest.split("/", 1)[0]
            if first:
                return first
    return None


def matches_core_model_path(path: str) -> bool:
    """True when a changed path is relevant to the core-model step.

    Mirrors the historical ``check_core_model_changes.matches_core_model_path``.
    """
    if path.endswith("_cluster.yml"):
        return False
    if any(path.startswith(p) for p in FULL_SUITE_PREFIXES):
        return True
    if path.startswith(MODEL_SOURCE_PREFIX) or path.startswith(MODEL_TEST_TREE):
        return True
    return False


def get_changed_core_model_files(branch: str) -> List[Tuple[str, str]]:
    """Return [(path, status), ...] for changed core-model files (upserts only)."""
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    changed = git_service.get_modified_files_from_diff(from_ref, "HEAD")
    files: List[Tuple[str, str]] = []
    for path, status in changed.items():
        if status in GitService.UPSERT_STATUS_CODES and matches_core_model_path(path):
            files.append((path, status))
    return files


def has_core_model_changes(branch: str) -> bool:
    return bool(get_changed_core_model_files(branch))


def _full_scope(changed_files, reason: str) -> Scope:
    return Scope(
        run_full=True,
        test_paths=list(FULL_TEST_PATHS),
        cov_sources=list(FULL_SOURCE_PATHS),
        changed_files=changed_files,
        fallback_reason=reason,
    )


def resolve_scope(branch: str) -> Scope:
    """Map the branch diff to the set of tests to run + sources to measure."""
    changed_files = get_changed_core_model_files(branch)

    models: List[str] = []
    for path, _ in changed_files:
        # Shared / base / CI-script change -> run everything (today's behavior).
        if any(path.startswith(p) for p in FULL_SUITE_PREFIXES):
            return _full_scope(changed_files, f"shared path changed: {path}")

        model = _extract_model(path)
        if model is None:
            # A core-model change that cannot be mapped to a single model — e.g.
            # the shared ``test/core_model_dags/conftest.py`` (matched by the
            # broad test tree but outside ``unit/core/<model>/``). A shared test
            # fixture can affect every model, so run the whole suite.
            return _full_scope(changed_files, f"unmapped core-model path: {path}")
        if model not in models:
            models.append(model)

    if not models:
        # No core-model changes at all (coverage.py normally only runs after
        # changes.py detects some; full suite is the safe default otherwise).
        return _full_scope(changed_files, "no core-model changes detected")

    missing = [m for m in models if not _model_test_dir_exists(m)]
    if missing:
        # New/unmapped model without a test dir -> safe fallback to full suite.
        return _full_scope(
            changed_files, f"model(s) without a test dir: {', '.join(missing)}"
        )

    return Scope(
        run_full=False,
        test_paths=[_model_test_path(m) for m in models],
        cov_sources=[_model_source_path(m) for m in models],
        models=models,
        changed_files=changed_files,
    )
