"""Contract tests for the Woodpecker ``tars_evals`` workflow.

Parses ``.woodpecker/tars_evals.yml`` as text/YAML enough to lock the
deployment contract the Markdown scenario suite mirrors: path filters,
step dependencies, dual stem files, ``--skip-hand-authored``, the empty
eval-scope guard, and gate exit propagation via ``run_dataset_queue.sh``.
"""

from __future__ import annotations

from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = REPO_ROOT / ".woodpecker" / "tars_evals.yml"


def _load_workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


def test_workflow_exists_and_excludes_development_prs():
    raw = WORKFLOW.read_text(encoding="utf-8")
    data = _load_workflow()
    assert data["when"]
    pr_when = next(item for item in data["when"] if item.get("event") == "pull_request")
    assert "development" in pr_when["branch"]["exclude"]
    assert "tars_evals_paths" in raw


def test_shared_path_filter_covers_docs_package_and_workflow():
    raw = WORKFLOW.read_text(encoding="utf-8")
    for needle in (
        "docs/llm_context/metric_entities/**/*.md",
        "docs/llm_context/business_entities/**/*.md",
        "packages/tars-evals/**",
        ".woodpecker/tars_evals.yml",
    ):
        assert needle in raw


def test_resolve_writes_dual_stem_files():
    raw = WORKFLOW.read_text(encoding="utf-8")
    assert "--write-eval-stems ./.tars-eval-stems" in raw
    assert "--write-scope-stems ./.tars-eval-expected-stems" in raw


def test_drift_step_uses_skip_hand_authored_and_git_diff():
    raw = WORKFLOW.read_text(encoding="utf-8")
    assert "--skip-hand-authored" in raw
    assert "git diff --exit-code -- packages/tars-evals/datasets/" in raw
    # Newly generated datasets are untracked until committed; plain `git diff`
    # alone would miss them and false-green the drift step.
    assert "git ls-files --others --exclude-standard -- packages/tars-evals/datasets/" in raw
    assert ".tars-eval-expected-stems" in raw


def test_eval_step_guards_empty_stems_before_queue():
    raw = WORKFLOW.read_text(encoding="utf-8")
    assert "if [ ! -s ./.tars-eval-stems ]; then" in raw
    assert "No changed dataset stems — nothing to evaluate." in raw
    assert "scripts/run_dataset_queue.sh $(cat \"$WORKSPACE/.tars-eval-stems\")" in raw


def test_eval_step_depends_on_scope_drift_and_credentials():
    data = _load_workflow()
    step = data["steps"]["tars-evals-changed"]
    assert set(step["depends_on"]) == {
        "resolve-eval-scope",
        "check-dataset-drift",
        "get-tars-eval-credentials",
    }
    assert data["steps"]["check-dataset-drift"]["depends_on"] == ["resolve-eval-scope"]


def test_eval_step_supports_sha_and_branch_skill_pins():
    raw = WORKFLOW.read_text(encoding="utf-8")
    assert "TARS_AITOOLS_REF may be a branch/tag OR a full commit SHA" in raw
    assert 'grep -Eq \'^[0-9a-f]{40}$\'' in raw
    assert 'fetch --depth 1 origin "$TARS_AITOOLS_REF"' in raw
    assert '--branch "$TARS_AITOOLS_REF"' in raw


def test_unit_tests_path_filter_is_package_scoped():
    raw = WORKFLOW.read_text(encoding="utf-8")
    assert "unit-tests-tars-evals" in raw
    assert "make test" in raw
    assert "make lint" in raw
    # Doc-only PRs must not be required to run the package unit suite.
    unit_block = raw.split("unit-tests-tars-evals:")[1].split("tars-evals-changed:")[0]
    assert "docs/llm_context" not in unit_block
    assert "packages/tars-evals/**" in unit_block
