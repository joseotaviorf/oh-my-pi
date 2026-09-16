"""Layer 0 — pure-function unit tests for changed_dataset_stems.py.

No git, filesystem, or subprocess calls: every function under test here takes
plain values (bytes, strings, sets, fakes) and returns plain values. Git/fs
integration lives in test_changed_dataset_stems_git.py; real-repo contract
checks live in test_changed_dataset_stems_contract.py; CLI/exit-code checks
live in test_changed_dataset_stems_cli.py.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "changed_dataset_stems.py"
_MODULE_NAME = "test_changed_dataset_stems_script"


def _load_module():
    spec = importlib.util.spec_from_file_location(_MODULE_NAME, SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # The script uses `from __future__ import annotations` with frozen
    # dataclasses; dataclasses resolves those string annotations via
    # sys.modules[cls.__module__], so the module must be registered before
    # exec_module runs (same reasoning as tars_evals.repo_bootstrap).
    sys.modules[_MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def cds():
    return _load_module()


def _entry(cds, status, path, old_path=None):
    return cds.DiffEntry(status=status, path=path, old_path=old_path)


# --------------------------------------------------------------------------
# resolve_diff_range
# --------------------------------------------------------------------------


def test_diff_range_explicit_base_and_head(cds):
    r = cds.resolve_diff_range(env={}, explicit_base="abc123", explicit_head="def456")
    assert (r.base, r.head, r.dotted, r.mode) == ("abc123", "def456", "..", "explicit")


def test_diff_range_explicit_base_only_defaults_head(cds):
    r = cds.resolve_diff_range(env={}, explicit_base="abc123", explicit_head=None)
    assert (r.base, r.head, r.mode) == ("abc123", "HEAD", "explicit")


def test_diff_range_explicit_head_only_defaults_base(cds):
    r = cds.resolve_diff_range(env={}, explicit_base=None, explicit_head="def456")
    assert (r.base, r.head, r.mode) == ("HEAD~1", "def456", "explicit")


def test_diff_range_explicit_wins_over_pull_request_env(cds):
    env = {"CI_PIPELINE_EVENT": "pull_request"}
    r = cds.resolve_diff_range(env=env, explicit_base="abc", explicit_head="def")
    assert r.mode == "explicit"


def test_diff_range_pull_request_uses_three_dot_origin_master(cds):
    env = {"CI_PIPELINE_EVENT": "pull_request"}
    r = cds.resolve_diff_range(env=env)
    assert (r.base, r.head, r.dotted, r.mode) == ("origin/master", "HEAD", "...", "pr")


def test_diff_range_push_uses_prev_and_current_sha(cds):
    env = {"CI_PREV_COMMIT_SHA": "aaa111", "CI_COMMIT_SHA": "bbb222"}
    r = cds.resolve_diff_range(env=env)
    assert (r.base, r.head, r.dotted, r.mode) == ("aaa111", "bbb222", "..", "push")


def test_diff_range_push_defaults_head_when_commit_sha_missing(cds):
    env = {"CI_PREV_COMMIT_SHA": "aaa111"}
    r = cds.resolve_diff_range(env=env)
    assert (r.base, r.head) == ("aaa111", "HEAD")


def test_diff_range_push_ignores_all_zero_prev_sha(cds):
    env = {"CI_PREV_COMMIT_SHA": "0" * 40, "CI_COMMIT_SHA": "bbb222"}
    r = cds.resolve_diff_range(env=env)
    assert r.mode == "fallback"


def test_diff_range_no_env_falls_back_to_head_minus_one(cds):
    r = cds.resolve_diff_range(env={})
    assert (r.base, r.head, r.dotted, r.mode) == ("HEAD~1", "HEAD", "..", "fallback")


def test_diff_range_blank_prev_sha_falls_back(cds):
    r = cds.resolve_diff_range(env={"CI_PREV_COMMIT_SHA": "   "})
    assert r.mode == "fallback"


def test_ensure_usable_keeps_valid_push_ancestor(cds):
    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["git", "cat-file"]:
            return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")
        if cmd[:2] == ["git", "merge-base"]:
            return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")
        raise AssertionError(cmd)

    original = cds.DiffRange("aaa111", "bbb222", "..", "push")
    ensured, warning = cds.ensure_usable_diff_range(
        original, cwd=Path("."), run=fake_run
    )
    assert ensured == original
    assert warning is None


def test_ensure_usable_falls_back_when_prev_sha_missing(cds):
    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["git", "cat-file"]:
            return SimpleNamespace(returncode=1, stdout=b"", stderr=b"missing")
        raise AssertionError(f"unexpected git call: {cmd}")

    original = cds.DiffRange("deadbeef", "bbb222", "..", "push")
    ensured, warning = cds.ensure_usable_diff_range(
        original, cwd=Path("."), run=fake_run
    )
    assert (ensured.base, ensured.head, ensured.dotted, ensured.mode) == (
        "HEAD~1",
        "HEAD",
        "..",
        "fallback",
    )
    assert warning is not None
    assert "deadbeef" in warning


def test_ensure_usable_falls_back_when_prev_sha_not_ancestor(cds):
    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["git", "cat-file"]:
            return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")
        if cmd[:2] == ["git", "merge-base"]:
            return SimpleNamespace(returncode=1, stdout=b"", stderr=b"")
        raise AssertionError(cmd)

    original = cds.DiffRange("sidebranch", "mastertip", "..", "push")
    ensured, warning = cds.ensure_usable_diff_range(
        original, cwd=Path("."), run=fake_run
    )
    assert ensured.mode == "fallback"
    assert warning is not None


def test_ensure_usable_leaves_pr_mode_alone(cds):
    original = cds.DiffRange("origin/master", "HEAD", "...", "pr")
    ensured, warning = cds.ensure_usable_diff_range(
        original,
        cwd=Path("."),
        run=lambda *a, **k: (_ for _ in ()).throw(AssertionError()),
    )
    assert ensured == original
    assert warning is None


# --------------------------------------------------------------------------
# parse_name_status_z
# --------------------------------------------------------------------------


def test_parse_name_status_z_empty_bytes(cds):
    assert cds.parse_name_status_z(b"") == []


def test_parse_name_status_z_single_modify(cds):
    raw = b"M\0foo.md\0"
    assert cds.parse_name_status_z(raw) == [cds.DiffEntry(status="M", path="foo.md")]


def test_parse_name_status_z_single_add(cds):
    raw = b"A\0foo.md\0"
    assert cds.parse_name_status_z(raw) == [cds.DiffEntry(status="A", path="foo.md")]


def test_parse_name_status_z_single_delete(cds):
    raw = b"D\0foo.md\0"
    assert cds.parse_name_status_z(raw) == [cds.DiffEntry(status="D", path="foo.md")]


def test_parse_name_status_z_rename_with_score(cds):
    raw = b"R100\0old.md\0new.md\0"
    entries = cds.parse_name_status_z(raw)
    assert entries == [cds.DiffEntry(status="R", path="new.md", old_path="old.md")]


def test_parse_name_status_z_copy_with_score(cds):
    raw = b"C075\0src.md\0dst.md\0"
    entries = cds.parse_name_status_z(raw)
    assert entries == [cds.DiffEntry(status="C", path="dst.md", old_path="src.md")]


def test_parse_name_status_z_multiple_entries(cds):
    raw = b"A\0a.md\0M\0b.md\0D\0c.md\0"
    entries = cds.parse_name_status_z(raw)
    assert [e.status for e in entries] == ["A", "M", "D"]
    assert [e.path for e in entries] == ["a.md", "b.md", "c.md"]


def test_parse_name_status_z_utf8_paths(cds):
    raw = "M\0docs/llm_context/metric_entities/café.md\0".encode()
    entries = cds.parse_name_status_z(raw)
    assert entries[0].path == "docs/llm_context/metric_entities/café.md"


def test_parse_name_status_z_truncated_simple_record_raises(cds):
    with pytest.raises(cds.DiffParseError):
        cds.parse_name_status_z(b"M\0")


def test_parse_name_status_z_truncated_rename_record_raises(cds):
    with pytest.raises(cds.DiffParseError):
        cds.parse_name_status_z(b"R100\0old.md\0")


def test_parse_name_status_z_empty_status_field_raises(cds):
    with pytest.raises(cds.DiffParseError):
        cds.parse_name_status_z(b"\0foo.md\0")


# --------------------------------------------------------------------------
# classify_paths
# --------------------------------------------------------------------------


def test_classify_paths_metric_doc(cds):
    entries = [_entry(cds, "M", "docs/llm_context/metric_entities/nps_fr.md")]
    classified = cds.classify_paths(entries)
    assert classified.metric_entries == tuple(entries)
    assert classified.business_entries == ()


def test_classify_paths_business_doc(cds):
    entries = [_entry(cds, "M", "docs/llm_context/domain_entities/nps.md")]
    classified = cds.classify_paths(entries)
    assert classified.business_entries == tuple(entries)
    assert classified.metric_entries == ()


def test_classify_paths_excludes_template(cds):
    entries = [
        _entry(cds, "M", "docs/llm_context/metric_entities/_TEMPLATE.md"),
        _entry(cds, "M", "docs/llm_context/domain_entities/_TEMPLATE.md"),
    ]
    classified = cds.classify_paths(entries)
    assert classified.metric_entries == ()
    assert classified.business_entries == ()


def test_classify_paths_ignores_nested_subdirectory(cds):
    entries = [_entry(cds, "M", "docs/llm_context/metric_entities/sub/nested.md")]
    classified = cds.classify_paths(entries)
    assert classified.metric_entries == ()
    assert classified.business_entries == ()


def test_classify_paths_ignores_unrelated_path(cds):
    entries = [_entry(cds, "M", "dags/cross/foo.sql")]
    classified = cds.classify_paths(entries)
    assert classified.metric_entries == ()
    assert classified.business_entries == ()


def test_classify_paths_rename_across_directories_matches_both(cds):
    entry = _entry(
        cds,
        "R",
        "docs/llm_context/metric_entities/foo.md",
        old_path="docs/llm_context/domain_entities/foo.md",
    )
    classified = cds.classify_paths([entry])
    assert classified.metric_entries == (entry,)
    assert classified.business_entries == (entry,)


def test_classify_paths_rename_within_same_directory_matches_once(cds):
    entry = _entry(
        cds,
        "R",
        "docs/llm_context/metric_entities/new_name.md",
        old_path="docs/llm_context/metric_entities/old_name.md",
    )
    classified = cds.classify_paths([entry])
    assert classified.metric_entries == (entry,)
    assert classified.business_entries == ()


# --------------------------------------------------------------------------
# metric_stems_from_entries
# --------------------------------------------------------------------------


def test_metric_stems_added(cds):
    changed, deleted = cds.metric_stems_from_entries(
        [_entry(cds, "A", "docs/llm_context/metric_entities/foo.md")]
    )
    assert changed == {"foo"}
    assert deleted == set()


def test_metric_stems_modified(cds):
    changed, deleted = cds.metric_stems_from_entries(
        [_entry(cds, "M", "docs/llm_context/metric_entities/foo.md")]
    )
    assert changed == {"foo"}
    assert deleted == set()


def test_metric_stems_deleted(cds):
    changed, deleted = cds.metric_stems_from_entries(
        [_entry(cds, "D", "docs/llm_context/metric_entities/foo.md")]
    )
    assert changed == set()
    assert deleted == {"foo"}


def test_metric_stems_renamed(cds):
    changed, deleted = cds.metric_stems_from_entries(
        [
            _entry(
                cds,
                "R",
                "docs/llm_context/metric_entities/new_name.md",
                old_path="docs/llm_context/metric_entities/old_name.md",
            )
        ]
    )
    assert changed == {"new_name"}
    assert deleted == {"old_name"}


def test_metric_stems_renamed_out_of_metric_entities_only_pruned_not_queued(cds):
    """A rename OUT of metric_entities/ (e.g. into domain_entities/) is kept
    by classify_paths (via old_path) so the old dataset gets pruned, but the
    new path is no longer a metric doc — it must NOT be queued for eval."""
    changed, deleted = cds.metric_stems_from_entries(
        [
            _entry(
                cds,
                "R",
                "docs/llm_context/domain_entities/moved_out.md",
                old_path="docs/llm_context/metric_entities/moved_out.md",
            )
        ]
    )
    assert changed == set()
    assert deleted == {"moved_out"}


def test_metric_stems_mixed_entries(cds):
    changed, deleted = cds.metric_stems_from_entries(
        [
            _entry(cds, "A", "docs/llm_context/metric_entities/a.md"),
            _entry(cds, "M", "docs/llm_context/metric_entities/b.md"),
            _entry(cds, "D", "docs/llm_context/metric_entities/c.md"),
        ]
    )
    assert changed == {"a", "b"}
    assert deleted == {"c"}


# --------------------------------------------------------------------------
# build_reverse_index
# --------------------------------------------------------------------------


def _fake_parse_markdown(related_by_stem):
    def parse(text, *, fallback_title=""):
        return SimpleNamespace(related_data_products=related_by_stem.get(text, []))

    return parse


def test_build_reverse_index_single_doc(cds):
    docs = {"nps_fr": "nps_fr-text"}
    parse = _fake_parse_markdown({"nps_fr-text": ["nps"]})
    index = cds.build_reverse_index(docs, parse_markdown=parse)
    assert index == {"nps": {"nps_fr"}}


def test_build_reverse_index_unions_multiple_metrics_for_same_business_id(cds):
    docs = {"nps_fr": "a", "offboard_human_vs_digital_metrics": "b"}
    parse = _fake_parse_markdown({"a": ["nps"], "b": ["nps"]})
    index = cds.build_reverse_index(docs, parse_markdown=parse)
    assert index == {"nps": {"nps_fr", "offboard_human_vs_digital_metrics"}}


def test_build_reverse_index_empty_docs(cds):
    assert cds.build_reverse_index({}, parse_markdown=_fake_parse_markdown({})) == {}


# --------------------------------------------------------------------------
# business_display_name / business_kebab_id
# --------------------------------------------------------------------------


def test_business_display_name_reads_h1(cds):
    assert cds.business_display_name("# Finance Revenue and Cost\n\n## Overview\n") == (
        "Finance Revenue and Cost"
    )


def test_business_display_name_ignores_h2_and_missing_h1(cds):
    assert cds.business_display_name("## Overview\n\nSome text.\n") is None


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("house_and_listing", "house-and-listing"),
        ("House and Listing", "house-and-listing"),
        ("nps", "nps"),
        ("fs-transact", "fs-transact"),
        # Accents collapse, but identically on both sides, so they still match.
        ("Consórcio", "cons-rcio"),
    ],
)
def test_business_kebab_id(cds, name, expected):
    assert cds.business_kebab_id(name) == expected


# --------------------------------------------------------------------------
# fan_out
# --------------------------------------------------------------------------


def test_fan_out_resolves_via_reverse_index(cds):
    entry = _entry(cds, "M", "docs/llm_context/domain_entities/nps.md")
    fanned = cds.fan_out(
        [entry],
        reverse_index={"nps": {"nps_fr"}},
        read_business_doc=lambda e: "# NPS\n",
    )
    assert fanned == {"nps_fr"}


def test_fan_out_resolves_via_h1_when_title_differs_from_filename(cds):
    """``finance_revenue_cost.md`` is titled "Finance Revenue and Cost", which
    is the name its five metric docs cite. Matching on the file stem alone
    silently resolved it to zero."""
    entry = _entry(cds, "M", "docs/llm_context/domain_entities/finance_revenue_cost.md")
    fanned = cds.fan_out(
        [entry],
        reverse_index={"finance-revenue-and-cost": {"ongoing_uc_fr"}},
        read_business_doc=lambda e: "# Finance Revenue and Cost\n\n## Overview\n",
    )
    assert fanned == {"ongoing_uc_fr"}


def test_fan_out_no_related_metrics_is_silent_zero(cds):
    """Most domain docs have no metric doc pointing at them — that is the
    normal state, not an anomaly, so it resolves to zero without a warning."""
    entry = _entry(cds, "A", "docs/llm_context/domain_entities/brand_new.md")
    fanned = cds.fan_out(
        [entry], reverse_index={}, read_business_doc=lambda e: "# Brand New\n"
    )
    assert fanned == set()


def test_fan_out_ignores_own_related_metric_entities_section(cds):
    """The domain side is no longer a source of the relationship: metric docs
    declare it upward and CI inverts that."""
    entry = _entry(cds, "M", "docs/llm_context/domain_entities/legacy.md")
    text = "# Legacy\n\n## Related Metric Entities\n\n- Listing To Rental\n"
    fanned = cds.fan_out(
        [entry], reverse_index={}, read_business_doc=lambda e: text
    )
    assert fanned == set()


def test_fan_out_deleted_doc_still_resolves_via_stem(cds):
    """A deleted doc can't be read, so the file stem is the only lookup left."""
    entry = _entry(cds, "D", "docs/llm_context/domain_entities/nps.md")
    fanned = cds.fan_out(
        [entry], reverse_index={"nps": {"nps_fr"}}, read_business_doc=lambda e: None
    )
    assert fanned == {"nps_fr"}


def test_fan_out_rename_resolves_via_old_path(cds):
    entry = _entry(
        cds,
        "R",
        "docs/llm_context/domain_entities/renamed_entity.md",
        old_path="docs/llm_context/domain_entities/original_entity.md",
    )
    fanned = cds.fan_out(
        [entry],
        reverse_index={"original-entity": {"related_metric"}},
        read_business_doc=lambda e: "# Renamed Entity\n",
    )
    assert fanned == {"related_metric"}


def test_fan_out_multiple_entries_unions_matches(cds):
    entries = [
        _entry(cds, "M", "docs/llm_context/domain_entities/nps.md"),
        _entry(cds, "A", "docs/llm_context/domain_entities/mystery.md"),
    ]
    fanned = cds.fan_out(
        entries,
        reverse_index={"nps": {"nps_fr"}},
        read_business_doc=lambda e: "# Doc\n",
    )
    assert fanned == {"nps_fr"}


# --------------------------------------------------------------------------
# load_business_ids / find_dangling_domain_references
# --------------------------------------------------------------------------


def test_load_business_ids_indexes_both_title_and_stem(cds, tmp_path):
    (tmp_path / "finance_revenue_cost.md").write_text(
        "# Finance Revenue and Cost\n", encoding="utf-8"
    )
    (tmp_path / "_TEMPLATE.md").write_text("# Template\n", encoding="utf-8")
    assert cds.load_business_ids(tmp_path) == {
        "finance-revenue-cost",
        "finance-revenue-and-cost",
    }


def test_load_business_ids_missing_dir_is_empty(cds, tmp_path):
    assert cds.load_business_ids(tmp_path / "nope") == set()


def test_find_dangling_domain_references_flags_unknown_business_id(cds):
    dangling = cds.find_dangling_domain_references(
        {"consorcio_cohort"},
        reverse_index={"cons-rcio-inside-sales-funnel": {"consorcio_cohort"}},
        known_business_ids={"cons-rcio"},
    )
    assert dangling == [("cons-rcio-inside-sales-funnel", ["consorcio_cohort"])]


def test_find_dangling_domain_references_ignores_known_business_id(cds):
    dangling = cds.find_dangling_domain_references(
        {"nps_fr"},
        reverse_index={"nps": {"nps_fr"}},
        known_business_ids={"nps"},
    )
    assert dangling == []


def test_find_dangling_domain_references_scoped_to_changed_metric_docs(cds):
    """A pre-existing bad bullet in an untouched doc must not warn on every
    unrelated PR — only the PR that changes the citing doc."""
    dangling = cds.find_dangling_domain_references(
        {"nps_fr"},
        reverse_index={"ghost-domain": {"some_other_metric"}, "nps": {"nps_fr"}},
        known_business_ids={"nps"},
    )
    assert dangling == []


# --------------------------------------------------------------------------
# count_items_in_text
# --------------------------------------------------------------------------


def test_count_items_column_zero_style(cds):
    text = "items:\n- id: a\n  question: q\n- id: b\n  question: q\n"
    assert cds.count_items_in_text(text) == 2


def test_count_items_indented_style(cds):
    text = "items:\n  - id: a\n    question: q\n"
    assert cds.count_items_in_text(text) == 1


def test_count_items_empty_list_flow_style(cds):
    assert cds.count_items_in_text("items: []\n") == 0


def test_count_items_no_items_key(cds):
    assert cds.count_items_in_text("other: 1\n") == 0


def test_count_items_ignores_multiline_block_scalar(cds):
    text = (
        "items:\n"
        "  - id: a\n"
        "    expected_query: |\n"
        "      SELECT 1\n"
        "      FROM foo\n"
        "  - id: b\n"
        "    expected_query: |\n"
        "      SELECT 2\n"
    )
    assert cds.count_items_in_text(text) == 2


def test_count_items_ignores_quoted_scalar_continuation_lines(cds):
    text = (
        "items:\n"
        "- id: a\n"
        '  expected_query: "SELECT 1\\n'
        '    \\ FROM foo"\n'
        "- id: b\n"
        '  expected_query: "SELECT 2"\n'
    )
    assert cds.count_items_in_text(text) == 2


def test_count_items_does_not_double_count_nested_list_field(cds):
    text = "items:\n  - id: a\n    tags:\n      - one\n      - two\n  - id: b\n"
    assert cds.count_items_in_text(text) == 2


# --------------------------------------------------------------------------
# apply_budget
# --------------------------------------------------------------------------


def test_apply_budget_under_limit_does_not_raise(cds):
    cds.apply_budget(5, max_samples=10, stems=["a"])


def test_apply_budget_exactly_at_limit_does_not_raise(cds):
    cds.apply_budget(10, max_samples=10, stems=["a"])


def test_apply_budget_over_limit_raises(cds):
    with pytest.raises(cds.BudgetExceededError) as exc_info:
        cds.apply_budget(11, max_samples=10, stems=["a", "b"])
    error = exc_info.value
    assert error.total_samples == 11
    assert error.max_samples == 10
    assert error.stems == ["a", "b"]
    assert "TARS_EVAL_MAX_SAMPLES=10" in str(error)


def test_apply_budget_zero_max_with_positive_total_raises(cds):
    with pytest.raises(cds.BudgetExceededError):
        cds.apply_budget(1, max_samples=0, stems=["a"])


# --------------------------------------------------------------------------
# partition_stems
# --------------------------------------------------------------------------


def test_partition_stems_changed_with_existing_dataset(cds):
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems={"a"},
        deleted_metric_stems=set(),
        fanned_out_stems=set(),
        fallback_to_all=False,
        all_stems=["a", "b"],
    )
    assert eval_stems == ["a"]
    assert scope_stems == ["a"]


def test_partition_stems_changed_without_dataset_yet(cds):
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems={"new_metric"},
        deleted_metric_stems=set(),
        fanned_out_stems=set(),
        fallback_to_all=False,
        all_stems=["a"],
    )
    assert eval_stems == []
    assert scope_stems == ["new_metric"]


def test_partition_stems_deleted_excluded_from_eval_but_kept_in_scope(cds):
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems=set(),
        deleted_metric_stems={"gone"},
        fanned_out_stems=set(),
        fallback_to_all=False,
        all_stems=["a"],
    )
    assert eval_stems == []
    assert scope_stems == ["gone"]


def test_partition_stems_fanned_out_included_when_dataset_exists(cds):
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems=set(),
        deleted_metric_stems=set(),
        fanned_out_stems={"nps_fr"},
        fallback_to_all=False,
        all_stems=["nps_fr"],
    )
    assert eval_stems == ["nps_fr"]
    assert scope_stems == ["nps_fr"]


def test_partition_stems_metadata_only_drops_eval_but_keeps_scope(cds):
    """The drift check stays broad while the expensive eval skips the stem."""
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems={"a"},
        deleted_metric_stems=set(),
        fanned_out_stems=set(),
        fallback_to_all=False,
        all_stems=["a", "b"],
        metadata_only_stems={"a"},
    )
    assert eval_stems == []
    assert scope_stems == ["a"]


def test_partition_stems_metadata_only_stem_still_evaluated_when_fanned_out(cds):
    """Fan-out is evidence of a real semantic change, so it wins over the filter."""
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems={"a"},
        deleted_metric_stems=set(),
        fanned_out_stems={"a"},
        fallback_to_all=False,
        all_stems=["a"],
        metadata_only_stems={"a"},
    )
    assert eval_stems == ["a"]
    assert scope_stems == ["a"]


def test_strip_h2_sections_removes_only_named_sections(cds):
    md = "# T\n\n## Ownership\n\nowner\n\n## Overview\n\nbody\n"
    stripped = cds.strip_h2_sections(md, frozenset({"ownership"}))
    assert "owner" not in stripped
    assert "## Overview" in stripped and "body" in stripped


def test_is_metadata_only_change_detects_ownership_edit(cds):
    old = "# T\n\n## Ownership\n\n- a@x.com\n\n## Overview\n\nbody\n"
    new = "# T\n\n## Ownership\n\n- b@x.com\n\n## Overview\n\nbody\n"
    assert cds.is_metadata_only_change(old, new) is True


def test_is_metadata_only_change_false_for_overview_edit(cds):
    old = "# T\n\n## Ownership\n\n- a@x.com\n\n## Overview\n\nbody\n"
    new = "# T\n\n## Ownership\n\n- a@x.com\n\n## Overview\n\nCHANGED\n"
    assert cds.is_metadata_only_change(old, new) is False


def test_is_metadata_only_change_false_when_golden_query_changes(cds):
    old = "# T\n\n## Ownership\n\n- a@x.com\n\n## Golden Queries\n\nSELECT 1\n"
    new = "# T\n\n## Ownership\n\n- b@x.com\n\n## Golden Queries\n\nSELECT 2\n"
    assert cds.is_metadata_only_change(old, new) is False


def test_normalize_entity_rename_contract_maps_heading_and_paths(cds):
    old = "## Related Business Entities\nsee `business_entities/visits.md`\n"
    new = "## Related Domain Entities\nsee `domain_entities/visits.md`\n"
    assert cds.normalize_entity_rename_contract(
        old
    ) == cds.normalize_entity_rename_contract(new)


def test_normalize_entity_rename_contract_ignores_line_endings(cds):
    old = "## Related Business Entities\r\n\r\n- Visits\r\n"
    new = "## Related Domain Entities\n\n- Visits\n"
    assert cds.normalize_entity_rename_contract(
        old
    ) == cds.normalize_entity_rename_contract(new)


def test_is_eval_irrelevant_change_true_for_heading_rename(cds):
    old = "# T\n\n## Related Business Entities\n\n- Visits\n\n## Golden Queries\n\nSELECT 1\n"
    new = "# T\n\n## Related Domain Entities\n\n- Visits\n\n## Golden Queries\n\nSELECT 1\n"
    assert cds.is_eval_irrelevant_change(old, new) is True


def test_is_contract_rename_only_true_for_heading_rename(cds):
    old = "# T\n\n## Related Business Entities\n\n- Visits\n"
    new = "# T\n\n## Related Domain Entities\n\n- Visits\n"
    assert cds.is_contract_rename_only(old, new) is True


def test_is_contract_rename_only_false_for_heading_plus_ownership(cds):
    old = "## Ownership\n\n- old@x.com\n\n## Related Business Entities\n\n- Visits\n"
    new = "## Ownership\n\n- new@x.com\n\n## Related Domain Entities\n\n- Visits\n"
    assert cds.is_contract_rename_only(old, new) is False


def test_is_eval_irrelevant_change_false_when_golden_query_changes(cds):
    old = "# T\n\n## Related Business Entities\n\n- Visits\n\n## Golden Queries\n\nSELECT 1\n"
    new = "# T\n\n## Related Domain Entities\n\n- Visits\n\n## Golden Queries\n\nSELECT 2\n"
    assert cds.is_eval_irrelevant_change(old, new) is False


def test_partition_stems_fallback_to_all_uses_full_corpus(cds):
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems=set(),
        deleted_metric_stems=set(),
        fanned_out_stems=set(),
        fallback_to_all=True,
        all_stems=["a", "b"],
    )
    assert eval_stems == ["a", "b"]
    assert scope_stems == ["a", "b"]


def test_partition_stems_fallback_still_includes_deleted_stems_in_scope(cds):
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems=set(),
        deleted_metric_stems={"gone"},
        fanned_out_stems=set(),
        fallback_to_all=True,
        all_stems=["a"],
    )
    assert eval_stems == ["a"]
    assert scope_stems == ["a", "gone"]


def test_partition_stems_fallback_includes_changed_and_fanned_stems_without_dataset(
    cds,
):
    eval_stems, scope_stems = cds.partition_stems(
        changed_metric_stems={"new_metric"},
        deleted_metric_stems=set(),
        fanned_out_stems={"fanned"},
        fallback_to_all=True,
        all_stems=["a"],
    )
    assert eval_stems == ["a"]
    assert scope_stems == ["a", "fanned", "new_metric"]
