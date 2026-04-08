"""
Guardrails for Woodpecker CI: valid YAML, clone settings for git diff HEAD~1,
and consistency of changed-DAG extraction used by release steps.

Runs under `make files-validation` (Woodpecker lint → files-validation-python).
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable, List

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
WOODPECKER_DIR = REPO_ROOT / ".woodpecker"

# Pipelines documented in .woodpecker/README.md as requiring parent commit for HEAD~1.
_PIPELINES_WITH_EXPLICIT_CLONE = ("release.yml", "tests.yml", "validations.yml")

# Same semantics as scripts/ci_cd/changed_dag_names_from_git.sh (git path lines → dag folder names).
def _changed_dag_names_from_diff_lines(lines: Iterable[str]) -> List[str]:
    names: set[str] = set()
    for raw in lines:
        line = raw.strip()
        if not line.startswith("dags/"):
            continue
        parts = line.split("/")
        if len(parts) >= 3:
            names.add(parts[2])
    return sorted(names)


def _woodpecker_yaml_files() -> List[Path]:
    return sorted(WOODPECKER_DIR.glob("*.yml"))


@pytest.mark.parametrize("yaml_path", _woodpecker_yaml_files(), ids=lambda p: p.name)
def test_woodpecker_yaml_parses(yaml_path: Path) -> None:
    text = yaml_path.read_text(encoding="utf-8")
    loaded = yaml.safe_load(text)
    assert loaded is not None, f"{yaml_path.name} must not be empty"
    assert isinstance(loaded, dict), f"{yaml_path.name} root must be a mapping"


@pytest.mark.parametrize("filename", _PIPELINES_WITH_EXPLICIT_CLONE)
def test_git_sensitive_pipeline_clone_settings(filename: str) -> None:
    path = WOODPECKER_DIR / filename
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    clone = doc.get("clone")
    assert clone is not None, f"{filename} must define clone: (see .woodpecker/README.md)"
    assert isinstance(clone, list) and len(clone) >= 1
    git_settings = clone[0].get("settings") or {}
    assert git_settings.get("partial") is False, f"{filename}: clone.settings.partial must be false"
    depth = git_settings.get("depth")
    assert isinstance(depth, int) and depth >= 2, f"{filename}: clone.settings.depth must be >= 2"


@pytest.mark.parametrize("filename", _woodpecker_yaml_files(), ids=lambda p: p.name)
def test_woodpecker_steps_non_empty(filename: Path) -> None:
    doc = yaml.safe_load(filename.read_text(encoding="utf-8"))
    steps = doc.get("steps")
    assert isinstance(steps, dict) and len(steps) > 0, f"{filename.name} must define a non-empty steps: mapping"


def test_changed_dag_extraction_sample_paths() -> None:
    diff_lines = [
        "README.md",
        "dags/for_rent/my_dag/queries/clean/foo.sql",
        "dags/for_rent/other_dag/metadata/enrich/bar.yml",
        "dags/for_rent/my_dag/spark_jobs/x.py",
    ]
    assert _changed_dag_names_from_diff_lines(diff_lines) == ["my_dag", "other_dag"]


def test_release_astronomer_deploy_depends_on_steps_visible_for_dags_only_changes() -> None:
    """If deploy runs on dags/**, every depends_on target must also match dags/**.

    Otherwise Woodpecker omits path-mismatched steps from the graph and fails with
    "depends on unknown step" on metadata/SQL-only DAG changes.
    """
    doc = yaml.safe_load((WOODPECKER_DIR / "release.yml").read_text(encoding="utf-8"))
    steps = doc["steps"]
    for deploy_key in ("astronomer-deploy-dags-forno", "astronomer-deploy-dags-prod"):
        deploy = steps[deploy_key]
        deploy_paths = deploy.get("when", {}).get("path", {}).get("include") or []
        if "dags/**" not in deploy_paths:
            continue
        for dep_name in deploy.get("depends_on", []):
            dep_paths = steps[dep_name].get("when", {}).get("path", {}).get("include") or []
            assert "dags/**" in dep_paths, (
                f"{deploy_key} runs on dags/** but depends on {dep_name} whose path "
                "does not include dags/** — Woodpecker drops that step on DAG-only diffs."
            )


_CHANGED_DAG_SCRIPT = REPO_ROOT / "scripts/ci_cd/changed_dag_names_from_git.sh"


def test_changed_dag_names_script_is_single_source_of_truth() -> None:
    """All release paths must call scripts/ci_cd/changed_dag_names_from_git.sh (not duplicate awk)."""
    script_text = _CHANGED_DAG_SCRIPT.read_text(encoding="utf-8")
    assert "git diff --name-only HEAD~1 HEAD" in script_text
    assert 'split($0, p, "/")' in script_text
    assert "print p[3]" in script_text

    upload_text = (REPO_ROOT / "scripts/ci_cd/upload_all_dag_package_artifacts_release.sh").read_text(
        encoding="utf-8"
    )
    assert "changed_dag_names_from_git.sh" in upload_text

    release_text = (WOODPECKER_DIR / "release.yml").read_text(encoding="utf-8")
    assert "create-dag-files-from-git-diff" in release_text


def test_makefile_create_dag_files_from_git_diff_invokes_shared_script() -> None:
    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
    assert "create-dag-files-from-git-diff" in makefile
    assert "changed_dag_names_from_git.sh" in makefile
