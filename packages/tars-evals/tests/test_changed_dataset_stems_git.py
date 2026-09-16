"""Layer 1 — real git-repo scenarios for changed_dataset_stems.py.

Exercises resolve_scope() end-to-end against a throwaway git work tree +
bare "origin" remote (see the tmp_git_repo fixture in conftest.py), using
the REAL document_parser (loaded via tars_evals.repo_bootstrap, unrelated to
the temp repo's own root — it always resolves to the actual bi-etl-ejuice
checkout on disk). This proves the git/diff-range mechanics feed the right
DiffEntry set into the pure resolution layer already covered by
test_changed_dataset_stems.py.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "changed_dataset_stems.py"
_MODULE_NAME = "test_changed_dataset_stems_git_script"

_METRIC_A = "docs/llm_context/metric_entities/metric_a.md"
_METRIC_B = "docs/llm_context/metric_entities/metric_b.md"
_BUSINESS_NPS = "docs/llm_context/domain_entities/biz_nps.md"
_DATASET_A = "packages/tars-evals/datasets/metric_a.yaml"

_METRIC_A_DOC_V1 = (
    "# Metric A\n\n## Overview\n\nv1\n\n"
    "## Related Domain Entities\n\n- Biz NPS\n\n## Golden Queries\n\nn/a\n"
)
_METRIC_A_DOC_V2 = _METRIC_A_DOC_V1.replace("v1", "v2")
_METRIC_B_DOC = "# Metric B\n\n## Overview\n\nv1\n\n## Golden Queries\n\nn/a\n"
_BUSINESS_NPS_DOC = "# Biz NPS\n\n## Overview\n\nv1\n"
_DATASET_A_YAML = "items:\n- id: a-1\n  question: q\n  expected_query: sql\n"


def _load_module():
    spec = importlib.util.spec_from_file_location(_MODULE_NAME, SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[_MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def cds():
    return _load_module()


@pytest.fixture(scope="module")
def parse_markdown(cds):
    return cds.load_document_parser().parse_entity_markdown


def _resolve(
    cds,
    repo,
    *,
    env,
    parse_markdown,
    max_samples=1000,
    explicit_base=None,
    explicit_head=None,
):
    diff_range = cds.resolve_diff_range(
        env=env, explicit_base=explicit_base, explicit_head=explicit_head
    )
    return cds.resolve_scope(
        repo_root=repo.path,
        diff_range=diff_range,
        datasets_dir=repo.path / "packages" / "tars-evals" / "datasets",
        parse_markdown=parse_markdown,
        max_samples=max_samples,
    )


def test_pr_mode_diffs_against_origin_master(cds, tmp_git_repo, parse_markdown):
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("add metric_a")
    # Not pushed -- origin/master still points at the fixture's initial commit.

    result = _resolve(
        cds,
        repo,
        env={"CI_PIPELINE_EVENT": "pull_request"},
        parse_markdown=parse_markdown,
    )

    assert result.eval_stems == ["metric_a"]
    assert result.scope_stems == ["metric_a"]
    assert not result.fallback_triggered


def test_ownership_only_edit_is_drift_checked_but_not_evaluated(
    cds, tmp_git_repo, parse_markdown
):
    """The CI case that blocked PR #27199: a Data Steward email edit.

    It cannot change what SQL is correct, so it must not spend ~4 minutes of
    eval or risk failing the gate on unrelated SQL — but it stays in the drift
    scope, which is cheap.
    """
    repo = tmp_git_repo
    doc_v1 = (
        "# Metric A\n\n## Ownership\n\n- old.steward@x.com\n\n"
        "## Overview\n\nv1\n\n## Golden Queries\n\nn/a\n"
    )
    repo.write(_METRIC_A, doc_v1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("add metric_a")
    repo.push_master()

    repo.write(_METRIC_A, doc_v1.replace("old.steward@x.com", "new.steward@x.com"))
    repo.commit("change the data steward")

    result = _resolve(
        cds,
        repo,
        env={"CI_PIPELINE_EVENT": "pull_request"},
        parse_markdown=parse_markdown,
    )

    assert result.eval_stems == [], "an ownership-only edit must not be evaluated"
    assert result.scope_stems == ["metric_a"], "but must still be drift-checked"
    assert result.metadata_only_stems == ["metric_a"]


def test_overview_edit_alongside_ownership_still_evaluates(
    cds, tmp_git_repo, parse_markdown
):
    """Only a change confined to eval-irrelevant sections may shrink the scope."""
    repo = tmp_git_repo
    doc_v1 = (
        "# Metric A\n\n## Ownership\n\n- old@x.com\n\n"
        "## Overview\n\nv1\n\n## Golden Queries\n\nn/a\n"
    )
    repo.write(_METRIC_A, doc_v1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("add metric_a")
    repo.push_master()

    repo.write(
        _METRIC_A,
        doc_v1.replace("old@x.com", "new@x.com").replace("v1", "v2"),
    )
    repo.commit("change steward and the overview")

    result = _resolve(
        cds,
        repo,
        env={"CI_PIPELINE_EVENT": "pull_request"},
        parse_markdown=parse_markdown,
    )

    assert result.eval_stems == ["metric_a"]
    assert result.metadata_only_stems == []


def test_related_domain_heading_rename_is_not_evaluated(
    cds, tmp_git_repo, parse_markdown
):
    """CI case for the business→domain rename: heading-only must not eval."""
    repo = tmp_git_repo
    doc_v1 = (
        "# Metric A\n\n## Overview\n\nv1\n\n"
        "## Related Business Entities\n\n- Biz NPS\n\n## Golden Queries\n\nn/a\n"
    )
    repo.write(_METRIC_A, doc_v1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("add metric_a")
    repo.push_master()

    repo.write(
        _METRIC_A,
        doc_v1.replace("Related Business Entities", "Related Domain Entities"),
    )
    repo.commit("rename related-entities heading")

    result = _resolve(
        cds,
        repo,
        env={"CI_PIPELINE_EVENT": "pull_request"},
        parse_markdown=parse_markdown,
    )

    assert result.eval_stems == []
    assert result.scope_stems == []
    assert result.metadata_only_stems == []
    assert result.contract_rename_only_stems == ["metric_a"]


def test_domain_folder_rename_does_not_fan_out_evals(cds, tmp_git_repo, parse_markdown):
    """git mv business_entities → domain_entities must not explode the sample budget."""
    repo = tmp_git_repo
    old_biz = "docs/llm_context/business_entities/biz_nps.md"
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.write(old_biz, _BUSINESS_NPS_DOC)
    repo.commit("baseline: metric_a relates to biz_nps")
    repo.push_master()

    repo.rename(old_biz, _BUSINESS_NPS)
    repo.commit("move domain entity folder")

    result = _resolve(
        cds,
        repo,
        env={"CI_PIPELINE_EVENT": "pull_request"},
        parse_markdown=parse_markdown,
    )

    assert result.eval_stems == []
    assert result.scope_stems == []


def test_newly_added_doc_is_always_evaluated(cds, tmp_git_repo, parse_markdown):
    """The filter only shrinks scope on positive evidence; an add has no old blob."""
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("add metric_a")

    result = _resolve(
        cds,
        repo,
        env={"CI_PIPELINE_EVENT": "pull_request"},
        parse_markdown=parse_markdown,
    )

    assert result.eval_stems == ["metric_a"]
    assert result.metadata_only_stems == []


def test_push_multi_commit_covers_both_commits(cds, tmp_git_repo, parse_markdown):
    repo = tmp_git_repo
    prev_sha = repo.rev_parse("HEAD")

    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.commit("commit 1 of push: add metric_a")
    repo.write(_METRIC_B, _METRIC_B_DOC)
    repo.commit("commit 2 of push: add metric_b")
    curr_sha = repo.rev_parse("HEAD")

    env = {"CI_PREV_COMMIT_SHA": prev_sha, "CI_COMMIT_SHA": curr_sha}
    result = _resolve(cds, repo, env=env, parse_markdown=parse_markdown)

    assert result.scope_stems == ["metric_a", "metric_b"]
    assert result.diff_range_warnings == []


def test_push_with_non_ancestor_prev_sha_falls_back_to_head_minus_one(
    cds, tmp_git_repo, parse_markdown
):
    """Woodpecker squash-merge case: CI_PREV_COMMIT_SHA is a PR-branch tip.

    The object may exist in a full clone but is not an ancestor of the
    squash commit on master. Scope must fall back to HEAD~1..HEAD instead
    of failing with ``Invalid revision range``.
    """
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("baseline metric_a on master")
    repo.push_master()

    repo._run("checkout", "-q", "-b", "feature")
    repo.write(_METRIC_B, _METRIC_B_DOC)
    repo.commit("feature-only commit")
    feature_tip = repo.rev_parse("HEAD")

    repo._run("checkout", "-q", "master")
    repo.write(_METRIC_A, _METRIC_A_DOC_V2)
    repo.commit("squash-like master tip: only metric_a changed")
    master_tip = repo.rev_parse("HEAD")

    env = {"CI_PREV_COMMIT_SHA": feature_tip, "CI_COMMIT_SHA": master_tip}
    result = _resolve(cds, repo, env=env, parse_markdown=parse_markdown)

    assert result.eval_stems == ["metric_a"]
    assert "metric_b" not in result.scope_stems
    assert result.diff_range_warnings
    assert feature_tip in result.diff_range_warnings[0]


def test_fallback_head_minus_one_sees_only_last_commit(
    cds, tmp_git_repo, parse_markdown
):
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.commit("commit 1: add metric_a")
    repo.write(_METRIC_B, _METRIC_B_DOC)
    repo.commit("commit 2: add metric_b")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    # No CI_PREV_COMMIT_SHA -> HEAD~1..HEAD -> only the last commit's change,
    # illustrating why push mode must use CI_PREV_COMMIT_SHA for multi-commit pushes.
    assert result.scope_stems == ["metric_b"]


def test_added_metric_doc_without_dataset_is_scope_only(
    cds, tmp_git_repo, parse_markdown
):
    repo = tmp_git_repo
    repo.write(_METRIC_B, _METRIC_B_DOC)
    repo.commit("add metric_b (no dataset yet)")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert result.scope_stems == ["metric_b"]
    assert result.eval_stems == []


def test_modified_metric_doc_with_dataset_is_eval_stem(
    cds, tmp_git_repo, parse_markdown
):
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("baseline: add metric_a + dataset")
    repo.write(_METRIC_A, _METRIC_A_DOC_V2)
    repo.commit("modify metric_a")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert result.eval_stems == ["metric_a"]


def test_deleted_metric_doc_pruned_from_eval_kept_in_scope(
    cds, tmp_git_repo, parse_markdown
):
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("baseline: add metric_a + dataset")
    repo.remove(_METRIC_A)
    repo.commit("delete metric_a doc")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert result.scope_stems == ["metric_a"]
    assert result.eval_stems == []


def test_renamed_metric_doc_old_stem_scope_new_stem_eval(
    cds, tmp_git_repo, parse_markdown
):
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("baseline: add metric_a + dataset")
    new_path = "docs/llm_context/metric_entities/metric_a_renamed.md"
    repo.rename(_METRIC_A, new_path)
    repo.write("packages/tars-evals/datasets/metric_a_renamed.yaml", _DATASET_A_YAML)
    repo.commit("rename metric_a -> metric_a_renamed")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert "metric_a" in result.scope_stems
    assert "metric_a" not in result.eval_stems
    assert "metric_a_renamed" in result.eval_stems


def test_business_doc_change_fans_out_via_reverse_index(
    cds, tmp_git_repo, parse_markdown
):
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)  # relates to "Biz NPS"
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.write(_BUSINESS_NPS, _BUSINESS_NPS_DOC)
    repo.commit("baseline: metric_a relates to biz_nps")
    repo.write(_BUSINESS_NPS, _BUSINESS_NPS_DOC.replace("v1", "v2"))
    repo.commit("modify biz_nps")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert result.eval_stems == ["metric_a"]
    assert not result.fallback_triggered


def test_business_doc_change_fans_out_via_h1_title_not_filename(
    cds, tmp_git_repo, parse_markdown
):
    """The metric doc cites the domain's *title*, which need not equal its
    filename — ``finance_revenue_cost.md`` is titled "Finance Revenue and
    Cost". Matching on the stem alone lost its five metric docs."""
    repo = tmp_git_repo
    path = "docs/llm_context/domain_entities/finance_revenue_cost.md"
    doc = "# Finance Revenue and Cost\n\n## Overview\n\nv1\n"
    repo.write(
        _METRIC_A,
        _METRIC_A_DOC_V1.replace("- Biz NPS", "- Finance Revenue and Cost"),
    )
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.write(path, doc)
    repo.commit("baseline: metric_a relates to finance revenue and cost")
    repo.write(path, doc.replace("v1", "v2"))
    repo.commit("modify the domain doc")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert result.eval_stems == ["metric_a"]
    assert result.scope_warnings == []


def test_metric_doc_citing_unknown_domain_entity_warns(
    cds, tmp_git_repo, parse_markdown
):
    """The typo is warned about on the metric side, where it can be fixed —
    not on every domain doc that happens to have no metrics."""
    repo = tmp_git_repo
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.write(_BUSINESS_NPS, _BUSINESS_NPS_DOC)
    repo.commit("baseline: domain doc present")
    repo.write(_METRIC_A, _METRIC_A_DOC_V1.replace("- Biz NPS", "- Ghost Domain"))
    repo.commit("add metric doc citing a domain nobody answers to")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert result.eval_stems == ["metric_a"]
    assert len(result.scope_warnings) == 1
    assert "ghost-domain" in result.scope_warnings[0]
    assert "metric_a" in result.scope_warnings[0]


def test_unlinked_business_doc_change_skips_eval_and_drift_without_warning(
    cds, tmp_git_repo, parse_markdown
):
    """A domain doc no metric doc points at resolves to zero stems quietly —
    with 60 domain docs and 44 metric docs, having no link is the common case,
    so warning about it drowned out the signal."""
    repo = tmp_git_repo
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.commit("baseline: unrelated dataset present")
    repo.write(
        "docs/llm_context/domain_entities/orphan.md",
        "# Orphan\n\n## Overview\n\nno relations\n",
    )
    repo.commit("add business doc with no metric relations")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert not result.fallback_triggered
    assert result.eval_stems == []
    assert result.scope_stems == []
    assert result.scope_warnings == []


def test_deleted_business_doc_still_fans_out_via_reverse_index(
    cds, tmp_git_repo, parse_markdown
):
    repo = tmp_git_repo
    repo.write(_METRIC_A, _METRIC_A_DOC_V1)  # relates to "Biz NPS"
    repo.write(_DATASET_A, _DATASET_A_YAML)
    repo.write(_BUSINESS_NPS, _BUSINESS_NPS_DOC)
    repo.commit("baseline: metric_a relates to biz_nps")
    repo.remove(_BUSINESS_NPS)
    repo.commit("delete biz_nps doc")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert not result.fallback_triggered
    assert result.eval_stems == ["metric_a"]


def test_empty_diff_yields_empty_scope(cds, tmp_git_repo, parse_markdown):
    repo = tmp_git_repo
    repo.commit("empty commit, no file changes")

    result = _resolve(cds, repo, env={}, parse_markdown=parse_markdown)

    assert result.eval_stems == []
    assert result.scope_stems == []
    assert not result.fallback_triggered


def test_missing_origin_remote_raises_actionable_git_diff_error(
    cds, tmp_path, parse_markdown
):
    lone = tmp_path / "lone_repo"
    lone.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "master", str(lone)], check=True)
    subprocess.run(
        ["git", "-C", str(lone), "config", "user.email", "test@example.com"], check=True
    )
    subprocess.run(["git", "-C", str(lone), "config", "user.name", "Test"], check=True)
    subprocess.run(
        ["git", "-C", str(lone), "commit", "-q", "--allow-empty", "-m", "init"],
        check=True,
    )

    diff_range = cds.resolve_diff_range(env={"CI_PIPELINE_EVENT": "pull_request"})
    with pytest.raises(cds.GitDiffError, match="origin/master"):
        cds.resolve_scope(
            repo_root=lone,
            diff_range=diff_range,
            datasets_dir=lone / "datasets",
            parse_markdown=parse_markdown,
            max_samples=1000,
        )
