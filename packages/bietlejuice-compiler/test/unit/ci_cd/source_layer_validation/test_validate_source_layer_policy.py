"""
Tests for source-layer policy CLI: PR-scoped DAG roots under dags/.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[6]))

from scripts.ci_cd.source_layer_validation.validate_source_layer_policy import (  # noqa: E402
    dag_roots_from_changed_files,
    get_branch_mode_affected_roots,
    is_valid_core_spark_dag_root,
    is_valid_dag_root,
    load_profile,
)


@pytest.fixture
def dags_profile():
    return load_profile("dags")


class TestGetBranchModeAffectedRoots:
    """Validation runs when any DAG under dags/ has M/A changes."""

    def test_skip_when_no_changes(self, dags_profile):
        skip_reason, roots = get_branch_mode_affected_roots({}, dags_profile)
        assert skip_reason is not None
        assert "No changes under" in skip_reason
        assert "dags/" in skip_reason
        assert roots == []

    def test_skip_when_only_outside_dags(self, dags_profile):
        changed = {
            "bietlejuice/base/foo.py": "A",
            "README.md": "M",
        }
        skip_reason, roots = get_branch_mode_affected_roots(changed, dags_profile)
        assert skip_reason is not None
        assert roots == []

    def test_skip_when_only_deleted_dag_file(self, dags_profile):
        changed = {"dags/core/core_region/spark_jobs/removed.yml": "D"}
        skip_reason, roots = get_branch_mode_affected_roots(changed, dags_profile)
        assert skip_reason is not None
        assert roots == []

    def test_skip_when_path_under_dags_but_not_valid_dag_root(self, dags_profile):
        changed = {"dags/README.md": "A"}
        skip_reason, roots = get_branch_mode_affected_roots(changed, dags_profile)
        assert skip_reason is not None
        assert "No DAG declaration folders affected" in skip_reason
        assert roots == []

    def test_run_when_for_rent_dag_modified(self, dags_profile):
        changed = {"dags/for_rent/dw_user/queries/dw/foo.sql": "M"}
        skip_reason, roots = get_branch_mode_affected_roots(changed, dags_profile)
        if is_valid_dag_root("dags/for_rent/dw_user"):
            assert skip_reason is None
            assert "dags/for_rent/dw_user" in roots
        else:
            assert skip_reason is not None or roots == []

    def test_run_when_core_dag_modified(self, dags_profile):
        changed = {"dags/core/core_region/spark_jobs/prod_conf.yml": "M"}
        skip_reason, roots = get_branch_mode_affected_roots(changed, dags_profile)
        if is_valid_dag_root("dags/core/core_region"):
            assert skip_reason is None
            assert "dags/core/core_region" in roots
        else:
            assert skip_reason is not None or roots == []


class TestDagRootsFromChangedFiles:
    def test_only_prefix_paths_contribute(self, dags_profile):
        paths = [
            "dags/core/core_region/spark_jobs/x.yml",
            "dags/for_rent/other/queries/dw/y.sql",
        ]
        roots = dag_roots_from_changed_files(paths, dags_profile)
        assert set(roots) == {"dags/core/core_region", "dags/for_rent/other"}

    def test_multiple_dags_deduplicated(self, dags_profile):
        paths = [
            "dags/core/core_region/spark_jobs/a.yml",
            "dags/core/core_region/metadata/core/b.yml",
            "dags/core/core_contract/spark_jobs/c.yml",
        ]
        roots = dag_roots_from_changed_files(paths, dags_profile)
        assert set(roots) == {"dags/core/core_region", "dags/core/core_contract"}
        assert len(roots) == 2


class TestIsValidDagRoot:
    def test_invalid_when_not_dir(self):
        assert is_valid_dag_root("/nonexistent/path") is False

    def test_invalid_when_no_declaration(self, tmp_path):
        (tmp_path / "fake_dag").mkdir()
        assert is_valid_dag_root(str(tmp_path / "fake_dag")) is False

    def test_valid_when_has_declaration(self, tmp_path):
        dag_dir = tmp_path / "my_dag"
        dag_dir.mkdir()
        (dag_dir / "my_dag_declaration.yml").write_text("dag: {}")
        assert is_valid_dag_root(str(dag_dir)) is True


class TestIsValidCoreSparkDagRootAlias:
    def test_alias_matches_is_valid_dag_root(self, tmp_path):
        dag_dir = tmp_path / "core_fake"
        dag_dir.mkdir()
        (dag_dir / "core_fake_declaration.yml").write_text("dag: {}")
        p = str(dag_dir)
        assert is_valid_core_spark_dag_root(p) == is_valid_dag_root(p)


class TestMainExitZeroWhenNoDagChanges:
    """Script exits 0 when no dags/ changes — does not block other CI."""

    @patch(
        "scripts.ci_cd.source_layer_validation.validate_source_layer_policy.GitService"
    )
    @patch(
        "scripts.ci_cd.source_layer_validation.validate_source_layer_policy.get_branch_mode_affected_roots"
    )
    def test_main_exits_zero_when_no_dag_changes(
        self, mock_affected, mock_git_class, dags_profile
    ):
        mock_git = MagicMock()
        mock_git.get_modified_files_from_diff.return_value = {}
        mock_git_class.return_value = mock_git
        mock_affected.return_value = (
            "No changes under dags/ — skipping source-layer policy check.",
            [],
        )
        with patch(
            "scripts.ci_cd.source_layer_validation.validate_source_layer_policy.load_profile",
            return_value=dags_profile,
        ):
            with patch(
                "sys.argv",
                [
                    "validate_source_layer_policy.py",
                    "--profile",
                    "dags",
                    "-b",
                    "feature",
                ],
            ):
                from scripts.ci_cd.source_layer_validation import (
                    validate_source_layer_policy as mod,
                )

                with pytest.raises(SystemExit) as exc_info:
                    mod.main()
                assert exc_info.value.code == 0


class TestCiStepNamesDoNotConflict:
    """New validation step must not clash with existing CI step names."""

    def test_woodpecker_step_name_is_unique(self):
        validations_yml = (
            Path(__file__).resolve().parents[6] / ".woodpecker" / "validations.yml"
        )
        content = validations_yml.read_text()
        steps = [
            line.strip().rstrip(":")
            for line in content.splitlines()
            if line.strip().startswith("validate-") and line.strip().endswith(":")
        ]
        assert "validate-source-layer-policy" in steps
        assert steps.count("validate-source-layer-policy") == 1

    def test_source_layer_policy_has_makefile_target(self):
        """Woodpecker step validate-source-layer-policy must have Makefile targets."""
        repo = Path(__file__).resolve().parents[6]
        makefile = repo / "Makefile"
        make_content = makefile.read_text()
        assert "validate-source-layer-policy" in make_content
        assert "validate-source-layer-policy-all" in make_content
