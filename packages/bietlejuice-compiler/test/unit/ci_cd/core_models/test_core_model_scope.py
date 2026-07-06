#!/usr/bin/env python3
"""Unit tests for the core-model scope resolver.

``GitService.get_modified_files_from_diff`` and ``resolve_diff_from_ref`` are
mocked so the tests are hermetic w.r.t. git; ``_model_test_dir_exists`` still hits
the real repo FS (real model test dirs exist under
``packages/bietlejuice-runtime/test/core_model_dags/unit/core/<model>``).
"""

import sys
from unittest.mock import patch

import pytest

sys.path.append(".")
from scripts.ci_cd.core_models import core_model_scope  # noqa: E402
from scripts.ci_cd.core_models.core_model_scope import (  # noqa: E402
    Scope,
    matches_core_model_path,
    resolve_scope,
)

# Real models with test dirs (verified 1:1 mapping in the plan).
MODEL_A = "core_region"
MODEL_B = "core_credit_evaluation"


def _mock_diff(files):
    """Return a patcher stack that makes the resolver see ``files``.

    ``files`` is a dict {path: status}.
    """
    return (
        patch.object(
            core_model_scope.GitService,
            "get_modified_files_from_diff",
            return_value=files,
        ),
        patch.object(
            core_model_scope, "resolve_diff_from_ref", return_value="origin/master"
        ),
    )


def _resolve(files) -> Scope:
    p1, p2 = _mock_diff(files)
    with p1, p2:
        return resolve_scope("feature/x")


class TestMatchesCoreModelPath:
    def test_model_source_path_matches(self):
        assert matches_core_model_path("dags/core/core_region/spark_jobs/x.py")

    def test_model_test_path_matches(self):
        assert matches_core_model_path(
            "packages/bietlejuice-runtime/test/core_model_dags/unit/core/core_region/x.py"
        )

    def test_shared_prefix_matches(self):
        assert matches_core_model_path(
            "packages/bietlejuice-runtime/src/bietlejuice/base/core_models/helpers/x.py"
        )

    def test_cluster_yml_ignored(self):
        assert not matches_core_model_path(
            "dags/core/core_region/core_region_cluster.yml"
        )

    def test_unrelated_path_ignored(self):
        assert not matches_core_model_path("dags/finance/enrich_x/queries/enrich/x.sql")

    def test_shared_test_tree_conftest_matches(self):
        # A shared file under test/core_model_dags/ but outside unit/core/ is
        # still core-model relevant (parity with Woodpecker's test tree).
        assert matches_core_model_path(
            "packages/bietlejuice-runtime/test/core_model_dags/conftest.py"
        )


class TestResolveScopePerModel:
    def test_single_model(self):
        scope = _resolve({f"dags/core/{MODEL_A}/spark_jobs/load.py": "M"})
        assert scope.run_full is False
        assert scope.models == [MODEL_A]
        assert scope.cov_sources == [f"dags/core/{MODEL_A}"]
        assert scope.test_paths == [
            f"packages/bietlejuice-runtime/test/core_model_dags/unit/core/{MODEL_A}/"
        ]

    def test_change_in_test_dir_maps_to_model(self):
        path = (
            f"packages/bietlejuice-runtime/test/core_model_dags/unit/core/{MODEL_A}/"
            "test_load.py"
        )
        scope = _resolve({path: "A"})
        assert scope.run_full is False
        assert scope.models == [MODEL_A]

    def test_multi_model_union(self):
        scope = _resolve(
            {
                f"dags/core/{MODEL_A}/spark_jobs/load.py": "M",
                f"dags/core/{MODEL_B}/spark_jobs/load.py": "A",
            }
        )
        assert scope.run_full is False
        assert set(scope.models) == {MODEL_A, MODEL_B}
        assert set(scope.cov_sources) == {
            f"dags/core/{MODEL_A}",
            f"dags/core/{MODEL_B}",
        }

    def test_cluster_yml_only_change_is_no_scope(self):
        # *_cluster.yml is filtered out -> no core-model changes at all.
        scope = _resolve({f"dags/core/{MODEL_A}/{MODEL_A}_cluster.yml": "M"})
        # No changed files -> resolve_scope falls back to full suite with reason.
        assert scope.run_full is True
        assert "no core-model changes detected" in scope.fallback_reason


class TestResolveScopeFullSuite:
    @pytest.mark.parametrize("prefix", list(core_model_scope.FULL_SUITE_PREFIXES))
    def test_shared_prefix_triggers_full(self, prefix):
        scope = _resolve({f"{prefix}some_file.py": "M"})
        assert scope.run_full is True
        assert scope.test_paths == core_model_scope.FULL_TEST_PATHS
        assert scope.cov_sources == core_model_scope.FULL_SOURCE_PATHS
        assert "shared path changed" in scope.fallback_reason

    def test_model_without_test_dir_falls_back(self):
        scope = _resolve({"dags/core/core_does_not_exist/spark_jobs/load.py": "M"})
        assert scope.run_full is True
        assert "without a test dir" in scope.fallback_reason

    def test_shared_conftest_triggers_full(self):
        # Regression: a shared file under test/core_model_dags/ (outside
        # unit/core/<model>/) cannot be mapped to a model and must run the full
        # suite, not be silently skipped.
        scope = _resolve(
            {"packages/bietlejuice-runtime/test/core_model_dags/conftest.py": "M"}
        )
        assert scope.run_full is True
        assert "unmapped core-model path" in scope.fallback_reason

    def test_shared_conftest_with_model_change_triggers_full(self):
        # Even alongside a mappable per-model change, the shared file forces full.
        scope = _resolve(
            {
                "packages/bietlejuice-runtime/test/core_model_dags/conftest.py": "M",
                f"dags/core/{MODEL_A}/spark_jobs/load.py": "M",
            }
        )
        assert scope.run_full is True
        assert "unmapped core-model path" in scope.fallback_reason

    def test_no_changes_falls_back_full(self):
        scope = _resolve({})
        assert scope.run_full is True

    def test_deleted_file_ignored(self):
        # Deletions (status D) are not upserts -> ignored; no changes -> full fallback.
        scope = _resolve({f"dags/core/{MODEL_A}/spark_jobs/load.py": "D"})
        assert scope.run_full is True


class TestExtractModel:
    def test_source_prefix(self):
        assert core_model_scope._extract_model("dags/core/core_region/x/y.py") == (
            "core_region"
        )

    def test_test_prefix(self):
        path = (
            "packages/bietlejuice-runtime/test/core_model_dags/unit/core/core_house/"
            "test_x.py"
        )
        assert core_model_scope._extract_model(path) == "core_house"

    def test_non_model_path_returns_none(self):
        assert core_model_scope._extract_model("packages/foo/bar.py") is None
