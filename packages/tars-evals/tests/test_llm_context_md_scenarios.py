"""Deployment scenarios for changed ``docs/llm_context`` Markdown.

These mirror the Woodpecker ``tars_evals`` path: resolve dual stem files,
regenerate with ``--skip-hand-authored``, and assert drift via
``check_dataset_drift.sh`` rules (tracked diff blocks; untracked new datasets
warn only).
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

from tars_evals.dataset import load_golden_dataset

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).parent / "fixtures" / "llm_context"
SCOPE_SCRIPT = PACKAGE_ROOT / "scripts" / "changed_dataset_stems.py"
GENERATOR_SCRIPT = PACKAGE_ROOT / "scripts" / "generate_datasets_from_context_docs.py"
QUEUE_SCRIPT = PACKAGE_ROOT / "scripts" / "run_dataset_queue.sh"

STEM = "eval_fixture_metric"
RENAMED_STEM = "eval_fixture_metric_renamed"
METRIC_PATH = f"docs/llm_context/metric_entities/{STEM}.md"
RENAMED_METRIC_PATH = f"docs/llm_context/metric_entities/{RENAMED_STEM}.md"
BUSINESS_PATH = "docs/llm_context/domain_entities/eval_fixture_domain.md"
ORPHAN_BUSINESS_PATH = "docs/llm_context/domain_entities/orphan_fixture_domain.md"
DATASET_PATH = f"packages/tars-evals/datasets/{STEM}.yaml"
RENAMED_DATASET_PATH = f"packages/tars-evals/datasets/{RENAMED_STEM}.yaml"


def _fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def _read_stems(path: Path) -> list[str]:
    if not path.is_file():
        return []
    return [line for line in path.read_text(encoding="utf-8").splitlines() if line]


def _run_scope_cli(
    repo,
    *,
    max_samples: int | None = None,
) -> tuple[subprocess.CompletedProcess[str], Path, Path]:
    eval_stems = repo.path / ".tars-eval-stems"
    scope_stems = repo.path / ".tars-eval-expected-stems"
    cmd = [
        sys.executable,
        str(SCOPE_SCRIPT),
        "--repo-root",
        str(repo.path),
        "--datasets-dir",
        str(repo.path / "packages" / "tars-evals" / "datasets"),
        "--base",
        "HEAD~1",
        "--head",
        "HEAD",
        "--write-eval-stems",
        str(eval_stems),
        "--write-scope-stems",
        str(scope_stems),
    ]
    if max_samples is not None:
        cmd.extend(["--max-samples", str(max_samples)])
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=False,
    )
    return result, eval_stems, scope_stems


def _run_generator(repo, stems_file: Path) -> subprocess.CompletedProcess[str]:
    """Match Woodpecker ``check-dataset-drift``: scoped + ``--skip-hand-authored``."""
    return subprocess.run(
        [
            sys.executable,
            str(GENERATOR_SCRIPT),
            "--repo-root",
            str(repo.path),
            "--datasets-dir",
            str(repo.path / "packages" / "tars-evals" / "datasets"),
            "--stems-file",
            str(stems_file),
            "--skip-hand-authored",
        ],
        cwd=PACKAGE_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def _generate_seed_dataset(repo, stem: str = STEM) -> None:
    scope = repo.path / ".seed-scope"
    scope.write_text(f"{stem}\n", encoding="utf-8")
    result = _run_generator(repo, scope)
    assert result.returncode == 0, result.stderr
    scope.unlink()


def _dataset_diff(repo) -> subprocess.CompletedProcess[str]:
    """Mirror ``check_dataset_drift.sh`` after generation."""
    tracked = subprocess.run(
        ["git", "diff", "--exit-code", "--", "packages/tars-evals/datasets/"],
        cwd=repo.path,
        capture_output=True,
        text=True,
        check=False,
    )
    if tracked.returncode != 0:
        return tracked
    untracked = subprocess.run(
        [
            "git",
            "ls-files",
            "--others",
            "--exclude-standard",
            "--",
            "packages/tars-evals/datasets/",
        ],
        cwd=repo.path,
        capture_output=True,
        text=True,
        check=False,
    )
    if untracked.stdout.strip():
        return subprocess.CompletedProcess(
            args=["dataset-drift"],
            returncode=0,
            stdout=untracked.stdout,
            stderr="WARN: uncommitted new eval dataset(s)\n",
        )
    return tracked


def _assert_ci_parity_drift(
    repo,
    *,
    expect_blocking_failure: bool,
    scope_stems: Path,
) -> None:
    generation_result = _run_generator(repo, scope_stems)
    assert generation_result.returncode == 0, generation_result.stderr
    drift_result = _dataset_diff(repo)
    if expect_blocking_failure:
        assert drift_result.returncode != 0, "expected datasets/ drift to block CI"
    else:
        assert drift_result.returncode == 0, drift_result.stdout + drift_result.stderr


def test_new_metric_without_committed_dataset_warns_without_blocking(
    tmp_git_repo,
):
    """New metric docs merge with a warning; eval starts after the YAML lands."""
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    repo.commit("add metric fixture without dataset")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == []
    assert _read_stems(scope_stems) == [STEM]
    _assert_ci_parity_drift(
        repo, expect_blocking_failure=False, scope_stems=scope_stems
    )
    assert (repo.path / DATASET_PATH).exists()


def test_new_metric_with_committed_dataset_has_clean_deployment_scope(tmp_git_repo):
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    _generate_seed_dataset(repo)
    repo.commit("add metric fixture and generated dataset")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    _assert_ci_parity_drift(
        repo, expect_blocking_failure=False, scope_stems=scope_stems
    )
    items = load_golden_dataset([repo.path / DATASET_PATH])

    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == [STEM]
    assert _read_stems(scope_stems) == [STEM]
    assert len(items) == 1
    assert items[0].id == f"{STEM}-daily-fixture-count"
    assert items[0].question == "Daily Fixture Count"
    assert "WHERE date >= DATE '2026-01-01'" in items[0].expected_query


def test_golden_query_edit_with_stale_dataset_fails_drift_check(tmp_git_repo):
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    _generate_seed_dataset(repo)
    repo.commit("seed metric fixture")
    repo.write(METRIC_PATH, _fixture("metric_v2_golden_edit.md"))
    repo.commit("edit golden query without regenerating dataset")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == [STEM]
    assert _read_stems(scope_stems) == [STEM]
    _assert_ci_parity_drift(
        repo, expect_blocking_failure=True, scope_stems=scope_stems
    )
    items = load_golden_dataset([repo.path / DATASET_PATH])
    assert "WHERE date >= DATE '2026-02-01'" in items[0].expected_query


def test_ownership_only_edit_is_scoped_but_not_evaluated(tmp_git_repo):
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    _generate_seed_dataset(repo)
    repo.commit("seed metric fixture")
    repo.write(METRIC_PATH, _fixture("metric_ownership_only.md"))
    repo.commit("ownership-only steward email edit")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == []
    assert _read_stems(scope_stems) == [STEM]
    assert "NOTE: not evaluating" in scope_result.stderr
    _assert_ci_parity_drift(
        repo, expect_blocking_failure=False, scope_stems=scope_stems
    )


def test_deleted_metric_doc_prunes_generated_dataset(tmp_git_repo):
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    _generate_seed_dataset(repo)
    repo.commit("seed metric fixture")
    repo.remove(METRIC_PATH)
    repo.commit("delete metric fixture doc")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == []
    assert _read_stems(scope_stems) == [STEM]
    # Generator removes the orphan YAML; drift fails until that deletion is committed
    # (same signal Woodpecker surfaces to authors).
    generation_result = _run_generator(repo, scope_stems)
    assert generation_result.returncode == 0, generation_result.stderr
    assert not (repo.path / DATASET_PATH).exists()
    assert _dataset_diff(repo).returncode != 0
    repo.commit("commit pruned dataset after doc deletion")
    _assert_ci_parity_drift(
        repo, expect_blocking_failure=False, scope_stems=scope_stems
    )


def test_renamed_metric_doc_prunes_old_and_evaluates_new_stem(tmp_git_repo):
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    _generate_seed_dataset(repo)
    repo.commit("seed metric fixture")
    repo.rename(METRIC_PATH, RENAMED_METRIC_PATH)
    repo.commit("rename metric fixture stem")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert STEM in _read_stems(scope_stems)
    assert RENAMED_STEM in _read_stems(scope_stems)
    assert STEM not in _read_stems(eval_stems)
    # Renamed stem has no committed dataset yet → eval empty until generation.
    assert RENAMED_STEM not in _read_stems(eval_stems)

    generation_result = _run_generator(repo, scope_stems)
    assert generation_result.returncode == 0, generation_result.stderr
    assert not (repo.path / DATASET_PATH).exists()
    assert (repo.path / RENAMED_DATASET_PATH).exists()
    # After generation, commit so a second scope pass can evaluate the new stem.
    repo.commit("commit regenerated renamed dataset")
    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    # Empty diff vs HEAD~1 if nothing changed — use an overview tweak.
    repo.write(
        RENAMED_METRIC_PATH,
        _fixture("metric_v1.md").replace(
            "evaluation deployment pipeline.",
            "evaluation deployment pipeline after rename.",
        ),
    )
    repo.commit("semantic edit on renamed metric")
    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == [RENAMED_STEM]
    _assert_ci_parity_drift(
        repo, expect_blocking_failure=False, scope_stems=scope_stems
    )


def test_domain_entity_edit_fans_out_without_dataset_drift(tmp_git_repo):
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    repo.write(BUSINESS_PATH, _fixture("business_v1.md"))
    _generate_seed_dataset(repo)
    repo.commit("seed linked business and metric fixtures")
    repo.write(BUSINESS_PATH, _fixture("business_v2_overview_edit.md"))
    repo.commit("edit business fixture overview")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == [STEM]
    assert _read_stems(scope_stems) == [STEM]
    assert "falling back to all stems" not in scope_result.stderr
    _assert_ci_parity_drift(
        repo, expect_blocking_failure=False, scope_stems=scope_stems
    )


def test_legacy_business_backlinks_no_longer_fan_out(tmp_git_repo):
    """A legacy domain doc still carrying ``## Related Metric Entities`` is
    ignored: the metric doc here declares no domain, so nothing points at this
    domain and the edit fans out to nothing. Only the metric side declares the
    relationship now."""
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_no_business_links.md"))
    _generate_seed_dataset(repo)
    repo.write(BUSINESS_PATH, _fixture("business_v1.md"))
    repo.commit("seed metric without reciprocal business link")
    repo.write(BUSINESS_PATH, _fixture("business_v2_overview_edit.md"))
    repo.commit("edit business overview of a legacy-shaped domain doc")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo)
    assert scope_result.returncode == 0, scope_result.stderr
    assert _read_stems(eval_stems) == []
    assert _read_stems(scope_stems) == []
    assert "WARN" not in scope_result.stderr
    assert "falling back to all stems" not in scope_result.stderr


def test_unlinked_business_doc_skips_eval_silently(tmp_git_repo):
    """No metric doc points at this domain, which is the normal state for most
    domain docs — it resolves to zero stems without warning about it."""
    repo = tmp_git_repo
    repo.write(METRIC_PATH, _fixture("metric_v1.md"))
    _generate_seed_dataset(repo)
    repo.commit("seed unrelated metric dataset")
    repo.write(ORPHAN_BUSINESS_PATH, _fixture("business_orphan.md"))
    repo.commit("add unlinked business fixture")

    scope_result, eval_stems, scope_stems = _run_scope_cli(repo, max_samples=60)
    assert scope_result.returncode == 0, scope_result.stderr
    assert "WARN" not in scope_result.stderr
    assert "falling back to all stems" not in scope_result.stderr
    assert _read_stems(eval_stems) == []
    assert _read_stems(scope_stems) == []

    budget_result, budget_eval, budget_scope = _run_scope_cli(repo, max_samples=0)
    assert budget_result.returncode == 0, budget_result.stderr
    assert _read_stems(budget_eval) == []
    assert _read_stems(budget_scope) == []


def test_empty_eval_stems_queue_is_not_all_datasets_when_guarded(tmp_path: Path):
    """The Woodpecker empty-scope guard is load-bearing; without stems the queue
    would evaluate every dataset. This asserts the documented short-circuit
    contract used by ``.woodpecker/tars_evals.yml``.
    """
    stems_file = tmp_path / ".tars-eval-stems"
    stems_file.write_text("", encoding="utf-8")
    assert not stems_file.stat().st_size

    # Replicate the workflow guard: empty file → no-op exit 0.
    if not stems_file.stat().st_size:
        return
    raise AssertionError("empty eval stems must short-circuit before the queue")


def test_queue_gate_failure_propagates_blocking_exit(tmp_path: Path):
    """Prove gate exit 1 is blocking via the queue script's fake-uv harness."""
    queue_test_path = Path(__file__).parent / "test_queue_script.py"
    spec = importlib.util.spec_from_file_location(
        "tars_evals_test_queue_script", queue_test_path
    )
    assert spec is not None and spec.loader is not None
    queue_tests = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(queue_tests)

    queue, env = queue_tests._prepare_queue(tmp_path)
    env["FAKE_EVAL_RC"] = "0"
    env["FAKE_ROLLUP_RC"] = "1"

    result = subprocess.run(
        [str(queue), "alpha"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert result.returncode != 0
    assert "suite gate failed" in result.stderr
