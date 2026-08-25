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
        "docs/llm_context/domain_entities/**/*.md",
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
    drift_script = REPO_ROOT / "packages/tars-evals/scripts/check_dataset_drift.sh"
    raw_drift = drift_script.read_text(encoding="utf-8")
    assert "scripts/check_dataset_drift.sh" in raw
    assert "--skip-hand-authored" in raw_drift
    assert "WARN: merge allowed" in raw_drift
    assert "git diff --exit-code" in raw_drift
    assert "git ls-files --others --exclude-standard" in raw_drift
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


def test_eval_step_archives_inspect_logs_to_tars_s3():
    raw = WORKFLOW.read_text(encoding="utf-8")
    assert "scripts/upload_inspect_logs_s3.py" in raw
    assert "TARS_EVAL_S3_BUCKET: 5a-tars-prod-data" in raw
    assert "TARS_EVAL_S3_PREFIX_ROOT: evals/inspect" in raw
    assert "TARS_EVAL_REQUIRE_S3_UPLOAD" in raw
    # Archive runs after gate reports and before propagating the eval RC.
    eval_block = raw.split("tars-evals-changed:")[1]
    assert eval_block.index("upload_inspect_logs_s3.py") < eval_block.index("exit $RC")


def test_required_s3_upload_failure_actually_fails_the_step():
    """TARS_EVAL_REQUIRE_S3_UPLOAD=1 must be able to fail this step — a plain
    `exit $RC` at the end would silently drop UPLOAD_RC and make the toggle a
    no-op even when upload_inspect_logs_s3.py itself returns non-zero."""
    raw = WORKFLOW.read_text(encoding="utf-8")
    eval_block = raw.split("tars-evals-changed:")[1]
    upload_idx = eval_block.index("upload_inspect_logs_s3.py")
    promote_idx = eval_block.index('RC=$UPLOAD_RC')
    exit_idx = eval_block.index("exit $RC")
    assert upload_idx < promote_idx < exit_idx
    # Only promoted when the eval gate itself passed — an eval failure must
    # stay the primary signal.
    assert 'if [ "$RC" -eq 0 ]; then' in eval_block


def test_eval_gate_is_advisory_and_cannot_block_a_pr():
    """An LLM judge grading SQL is not a deterministic check, so the gate
    reports rather than blocks. `failure: ignore` is what makes a red gate
    non-fatal to the workflow, the PR, and any deployment."""
    data = _load_workflow()

    assert data["steps"]["tars-evals-changed"]["failure"] == "ignore"


def test_deterministic_steps_still_block():
    """Only the judge-scored gate is advisory. Scope resolution, dataset drift
    and the package unit suite have a single correct answer, so a failure there
    is a real mistake and must keep failing the pipeline."""
    data = _load_workflow()

    for step in ("resolve-eval-scope", "check-dataset-drift", "unit-tests-tars-evals"):
        assert "failure" not in data["steps"][step], (
            f"{step} must stay blocking — it does not depend on a judge's opinion"
        )


def test_advisory_gate_still_announces_its_failure_mode():
    """A quiet red step inside a green pipeline gets ignored. The step must
    still distinguish 'SQL quality regressed' from 'the harness broke'."""
    raw = WORKFLOW.read_text(encoding="utf-8")
    eval_block = raw.split("tars-evals-changed:")[1]

    assert "TARS EVAL GATE FAILED ON SQL QUALITY" in eval_block
    assert "TARS EVAL GATE PRODUCED NO RESULT" in eval_block
    assert 'if [ "$RC" -eq 1 ]; then' in eval_block
    # The banner must come after the archive and before the step exits.
    assert eval_block.index("TARS EVAL GATE FAILED") > eval_block.index(
        "upload_inspect_logs_s3.py"
    )


def test_unit_tests_path_filter_is_package_scoped():
    raw = WORKFLOW.read_text(encoding="utf-8")
    assert "unit-tests-tars-evals" in raw
    assert "make test" in raw
    assert "make lint" in raw
    # Doc-only PRs must not be required to run the package unit suite.
    unit_block = raw.split("unit-tests-tars-evals:")[1].split("tars-evals-changed:")[0]
    assert "docs/llm_context" not in unit_block
    assert "packages/tars-evals/**" in unit_block
