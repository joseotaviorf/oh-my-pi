from pathlib import Path
from types import SimpleNamespace

import pytest
from tars_evals import generate_from_context as gfc
from tars_evals.dataset import load_golden_dataset
from tars_evals.generate_from_context import (
    DatasetItem,
    build_items,
    entity_h1_title,
    generate_datasets,
    is_auto_generated,
    load_document_parser,
    make_item_id,
    parse_stems_file,
    render_dataset_yaml,
    repo_root,
    resolve_selected_stems,
    singular_golden_h2_title,
    slugify,
    strip_query_prefix,
)


def test_strip_query_prefix_drops_query_n_emdash():
    assert (
        strip_query_prefix("Query 1 — Monthly Global Turnover")
        == "Monthly Global Turnover"
    )


def test_strip_query_prefix_drops_numbered_dot():
    assert strip_query_prefix("1. Active agents per hub") == "Active agents per hub"


def test_strip_query_prefix_leaves_plain_title():
    assert strip_query_prefix("Active agents per hub") == "Active agents per hub"


def test_strip_query_prefix_drops_golden_query_label():
    assert strip_query_prefix("Query 1 — Golden query") == ""
    assert (
        strip_query_prefix("Golden query: Active agents per hub")
        == "Active agents per hub"
    )
    assert strip_query_prefix("Query 1 — 1. Quality Pub") == "Quality Pub"


def test_entity_h1_title():
    assert entity_h1_title("# % Escalation Rate (Wall-E)\n\n## Ownership\n") == (
        "% Escalation Rate (Wall-E)"
    )


def test_slugify_basic():
    assert slugify("Monthly Global Turnover") == "monthly-global-turnover"


def test_make_item_id_prefixes_stem_and_disambiguates():
    used: set[str] = set()
    a = make_item_id("turnover", "Monthly Global Turnover", used)
    b = make_item_id("turnover", "Monthly Global Turnover", used)
    assert a == "turnover-monthly-global-turnover"
    assert b == "turnover-monthly-global-turnover-2"
    assert used == {a, b}


def test_is_auto_generated_missing_file_is_writable(tmp_path: Path):
    assert is_auto_generated(tmp_path / "new.yaml") is True


def test_is_auto_generated_requires_exact_header(tmp_path: Path):
    hand = tmp_path / "chatbot.yaml"
    hand.write_text("items:\n  - id: x\n", encoding="utf-8")
    gen = tmp_path / "turnover.yaml"
    gen.write_text("# auto-generated\nitems: []\n", encoding="utf-8")
    assert is_auto_generated(hand) is False
    assert is_auto_generated(gen) is True


def test_singular_golden_h2_title():
    md = "# Agents\n\n## Golden query: Active agents per hub\n\n```sql\nSELECT 1\n```\n"
    assert singular_golden_h2_title(md) == "Active agents per hub"


def test_build_items_from_h3_titles():
    goldens = [
        SimpleNamespace(name="Query 1 — Monthly Global Turnover", sql="SELECT 1"),
        SimpleNamespace(name="Query 2 — Monthly Hub Turnover", sql="SELECT 2"),
    ]
    items, warnings = build_items("turnover", goldens, markdown="# Turnover\n")
    assert [i.id for i in items] == [
        "turnover-monthly-global-turnover",
        "turnover-monthly-hub-turnover",
    ]
    assert items[0].question == "Monthly Global Turnover"
    assert items[0].expected_query == "SELECT 1"
    assert warnings == []


def test_build_items_recovers_singular_h2_title():
    md = "## Golden query: Active agents per hub\n\n```sql\nSELECT 1\n```\n"
    goldens = [SimpleNamespace(name="Query 1 — Golden query", sql="SELECT 1")]
    items, warnings = build_items("agents", goldens, markdown=md)
    assert items[0].question == "Active agents per hub"
    assert items[0].id == "agents-active-agents-per-hub"
    assert warnings == []


def test_build_items_falls_back_to_h1_when_bare_golden_query():
    md = "# Escalation Rate FR Offboarding\n\n## Golden Queries\n\n```sql\nSELECT 1\n```\n"
    goldens = [SimpleNamespace(name="Query 1 — Golden query", sql="SELECT 1")]
    items, warnings = build_items(
        "escalation_rate_fr_offboarding", goldens, markdown=md
    )
    assert items[0].question == "Escalation Rate FR Offboarding"
    assert (
        items[0].id == "escalation_rate_fr_offboarding-escalation-rate-fr-offboarding"
    )
    assert warnings == []


def test_build_items_disambiguates_duplicate_titles():
    goldens = [
        SimpleNamespace(name="Query 1 — Same Title", sql="SELECT 1"),
        SimpleNamespace(name="Query 2 — Same Title", sql="SELECT 2"),
    ]
    items, warnings = build_items("foo", goldens, markdown="")
    assert items[0].id == "foo-same-title"
    assert items[1].id == "foo-same-title-2"
    assert any("duplicate" in w.lower() or "disambiguat" in w.lower() for w in warnings)


def test_build_items_skips_empty_sql():
    goldens = [SimpleNamespace(name="Query 1 — Empty", sql="")]
    items, warnings = build_items("foo", goldens, markdown="")
    assert items == []


def test_build_items_excludes_scaffolding_and_incomplete_sql():
    goldens = [
        SimpleNamespace(name="Query 1 — Base CTE (shared)", sql="WITH x AS (SELECT 1)"),
        SimpleNamespace(
            name="Query 2 — Weekly rate",
            sql="SELECT week_start, COUNT(*) AS n FROM dw.fact GROUP BY 1",
        ),
        SimpleNamespace(
            name="Query 3 — Fragment",
            sql="-- Uses base CTE above (tb_fl)\nSELECT week_start FROM tb_fl",
        ),
    ]
    items, warnings = build_items("foo", goldens, markdown="")
    assert len(items) == 1
    assert items[0].question == "Weekly rate"
    assert any("excluded eval item" in w for w in warnings)


def test_render_dataset_yaml_header_and_fields():
    text = render_dataset_yaml(
        [DatasetItem("turnover-monthly", "Monthly", "SELECT 1")],
        source_relpath="docs/llm_context/metric_entities/turnover.md",
    )
    assert text.startswith("# auto-generated\n")
    assert "docs/llm_context/metric_entities/turnover.md" in text.splitlines()[1]
    assert "id: turnover-monthly" in text
    assert "question:" in text
    assert "Monthly" in text
    assert "expected_query:" in text
    assert "SELECT 1" in text


def test_render_dataset_yaml_loads_via_dataset_loader(tmp_path: Path):
    text = render_dataset_yaml(
        [DatasetItem("turnover-monthly", "Monthly", "SELECT 1")],
        source_relpath="docs/llm_context/metric_entities/turnover.md",
    )
    path = tmp_path / "turnover.yaml"
    path.write_text(text, encoding="utf-8")
    items = load_golden_dataset([path])
    assert len(items) == 1
    assert items[0].id == "turnover-monthly"
    assert items[0].question == "Monthly"
    assert items[0].expected_query.strip() == "SELECT 1"


def test_generate_datasets_metric_entities_only(tmp_path: Path):
    """Business markdown must not produce YAML; metric markdown must."""
    root = tmp_path / "repo"
    biz = root / "docs/llm_context/business_entities"
    met = root / "docs/llm_context/metric_entities"
    biz.mkdir(parents=True)
    met.mkdir(parents=True)
    datasets = tmp_path / "datasets"
    datasets.mkdir()

    (biz / "agents.md").write_text(
        "# Agents\n\n## Golden Queries\n\n### Q1\n\n```sql\nSELECT 1\n```\n",
        encoding="utf-8",
    )
    (met / "turnover.md").write_text(
        "# Turnover\n\n## Golden Queries\n\n### Monthly\n\n```sql\nSELECT 2\n```\n",
        encoding="utf-8",
    )
    # Stale business auto-gen that must be pruned:
    stale = datasets / "agents.yaml"
    stale.write_text(
        "# auto-generated\n# source: docs/llm_context/business_entities/agents.md\nitems: []\n",
        encoding="utf-8",
    )
    # Hand-authored must survive prune:
    hand = datasets / "accounting.yaml"
    hand.write_text(
        "items:\n- id: a\n  question: q\n  expected_query: SELECT 1\n",
        encoding="utf-8",
    )

    def fake_parse(text: str, fallback_title: str = ""):
        # Minimal: one golden if ```sql present
        if "```sql" not in text:
            return SimpleNamespace(golden_queries=[])
        sql = "SELECT 2" if "Turnover" in text else "SELECT 1"
        return SimpleNamespace(
            golden_queries=[SimpleNamespace(name="Query 1 — Title", sql=sql)]
        )

    rc = generate_datasets(
        llm_context_dir=root / "docs/llm_context",
        datasets_dir=datasets,
        dry_run=False,
        parse_markdown=fake_parse,
        repo_root=root,
    )
    assert rc == 0
    assert not (datasets / "agents.yaml").exists(), "business auto-gen must be pruned"
    assert (datasets / "turnover.yaml").exists()
    assert (datasets / "accounting.yaml").exists()
    assert "# source: docs/llm_context/metric_entities/turnover.md" in (
        datasets / "turnover.yaml"
    ).read_text(encoding="utf-8")


def test_generate_datasets_writes_and_prunes(tmp_path: Path):
    llm = tmp_path / "docs" / "llm_context"
    (llm / "business_entities").mkdir(parents=True)
    (llm / "metric_entities").mkdir(parents=True)
    md = llm / "metric_entities" / "turnover.md"
    md.write_text(
        "# Turnover\n\n## Golden Queries\n\n### Query 1 — Monthly\n\n```sql\nSELECT 1\n```\n"
    )

    datasets = tmp_path / "datasets"
    datasets.mkdir()
    orphan = datasets / "gone.yaml"
    orphan.write_text("# auto-generated\nitems: []\n", encoding="utf-8")
    hand = datasets / "chatbot.yaml"
    hand.write_text(
        "items:\n  - id: keep\n    question: q\n    expected_query: |\n      SELECT 1\n",
        encoding="utf-8",
    )

    class Parsed:
        golden_queries = [SimpleNamespace(name="Query 1 — Monthly", sql="SELECT 1")]

    def fake_parse(text: str, fallback_title: str = ""):
        return Parsed()

    code = generate_datasets(
        llm_context_dir=llm,
        datasets_dir=datasets,
        dry_run=False,
        parse_markdown=fake_parse,
        repo_root=tmp_path,
    )
    assert code == 0
    out = datasets / "turnover.yaml"
    assert out.exists()
    assert out.read_text(encoding="utf-8").startswith("# auto-generated\n")
    assert not orphan.exists()
    assert hand.exists()


def test_generate_datasets_prunes_when_goldens_disappear(tmp_path: Path):
    llm = tmp_path / "docs" / "llm_context"
    (llm / "business_entities").mkdir(parents=True)
    (llm / "metric_entities").mkdir(parents=True)
    md = llm / "metric_entities" / "turnover.md"
    md.write_text("# Turnover\n\n## Overview\n\nx\n")  # no golden section

    datasets = tmp_path / "datasets"
    datasets.mkdir()
    stale = datasets / "turnover.yaml"
    stale.write_text(
        "# auto-generated\nitems:\n  - id: turnover-old\n    question: Old\n    expected_query: |\n      SELECT 1\n",
        encoding="utf-8",
    )

    class Parsed:
        golden_queries = []

    code = generate_datasets(
        llm_context_dir=llm,
        datasets_dir=datasets,
        dry_run=False,
        parse_markdown=lambda text, fallback_title="": Parsed(),
        repo_root=tmp_path,
    )
    assert code == 0
    assert not stale.exists()


def test_generate_datasets_dry_run_writes_nothing(tmp_path: Path):
    llm = tmp_path / "docs" / "llm_context"
    (llm / "business_entities").mkdir(parents=True)
    (llm / "metric_entities").mkdir(parents=True)
    (llm / "metric_entities" / "turnover.md").write_text(
        "# Turnover\n\n## Golden Queries\n\n### Query 1 — Monthly\n\n```sql\nSELECT 1\n```\n"
    )
    datasets = tmp_path / "datasets"
    datasets.mkdir()
    orphan = datasets / "gone.yaml"
    orphan.write_text("# auto-generated\nitems: []\n", encoding="utf-8")

    class Parsed:
        golden_queries = [SimpleNamespace(name="Query 1 — Monthly", sql="SELECT 1")]

    code = generate_datasets(
        llm_context_dir=llm,
        datasets_dir=datasets,
        dry_run=True,
        parse_markdown=lambda text, fallback_title="": Parsed(),
        repo_root=tmp_path,
    )
    assert code == 0
    assert not (datasets / "turnover.yaml").exists()
    assert orphan.exists()


def test_generate_datasets_dry_run_skips_mkdir_when_dir_missing(tmp_path: Path):
    """Dry-run must not create datasets_dir (zero filesystem writes)."""
    llm = tmp_path / "docs" / "llm_context"
    (llm / "metric_entities").mkdir(parents=True)
    (llm / "metric_entities" / "turnover.md").write_text(
        "# Turnover\n\n## Golden Queries\n\n### Query 1 — Monthly\n\n```sql\nSELECT 1\n```\n",
        encoding="utf-8",
    )
    datasets = tmp_path / "datasets"
    assert not datasets.exists()

    class Parsed:
        golden_queries = [SimpleNamespace(name="Query 1 — Monthly", sql="SELECT 1")]

    code = generate_datasets(
        llm_context_dir=llm,
        datasets_dir=datasets,
        dry_run=True,
        parse_markdown=lambda text, fallback_title="": Parsed(),
        repo_root=tmp_path,
    )
    assert code == 0
    assert not datasets.exists()


def test_generate_datasets_refuses_hand_collision_without_writes(tmp_path: Path):
    llm = tmp_path / "docs" / "llm_context"
    (llm / "business_entities").mkdir(parents=True)
    (llm / "metric_entities").mkdir(parents=True)
    (llm / "metric_entities" / "accounting.md").write_text(
        "# Accounting\n\n## Golden Queries\n\n### Query 1 — Rate\n\n```sql\nSELECT 1\n```\n"
    )
    (llm / "metric_entities" / "turnover.md").write_text(
        "# Turnover\n\n## Golden Queries\n\n### Query 1 — Monthly\n\n```sql\nSELECT 2\n```\n"
    )
    datasets = tmp_path / "datasets"
    datasets.mkdir()
    (datasets / "accounting.yaml").write_text(
        "items:\n  - id: hand\n    question: q\n    expected_query: |\n      SELECT 1\n",
        encoding="utf-8",
    )
    orphan = datasets / "gone.yaml"
    orphan.write_text("# auto-generated\nitems: []\n", encoding="utf-8")

    class Parsed:
        def __init__(self, sql: str):
            self.golden_queries = [SimpleNamespace(name="Query 1 — X", sql=sql)]

    def fake_parse(text: str, fallback_title: str = ""):
        return Parsed("SELECT 1" if fallback_title == "accounting" else "SELECT 2")

    code = generate_datasets(
        llm_context_dir=llm,
        datasets_dir=datasets,
        dry_run=False,
        parse_markdown=fake_parse,
        repo_root=tmp_path,
    )
    assert code == 1
    assert "id: hand" in (datasets / "accounting.yaml").read_text(encoding="utf-8")
    assert not (datasets / "turnover.yaml").exists()  # fail-fast: no partial writes
    assert orphan.exists()  # fail-fast: no prune either


def test_generate_datasets_skips_zero_goldens(tmp_path: Path):
    llm = tmp_path / "docs" / "llm_context"
    (llm / "business_entities").mkdir(parents=True)
    (llm / "metric_entities").mkdir(parents=True)
    (llm / "business_entities" / "empty.md").write_text("# Empty\n\n## Overview\n\nx\n")
    datasets = tmp_path / "datasets"
    datasets.mkdir()

    class Parsed:
        golden_queries = []

    code = generate_datasets(
        llm_context_dir=llm,
        datasets_dir=datasets,
        dry_run=False,
        parse_markdown=lambda text, fallback_title="": Parsed(),
        repo_root=tmp_path,
    )
    assert code == 0
    assert not (datasets / "empty.yaml").exists()


def test_repo_root_finds_llm_context():
    root = repo_root()
    assert (root / "docs" / "llm_context").is_dir()


def test_live_parser_singular_h2_becomes_question():
    parser = load_document_parser()
    md = (
        "# Agents\n\n"
        "## Golden query: Active agents per hub\n\n"
        "Daily snapshot.\n\n"
        "```sql\nSELECT hub_name FROM dw.fact_agents\n```\n"
    )
    parsed = parser.parse_entity_markdown(md, fallback_title="agents")
    assert parsed.golden_queries, "expected at least one golden from singular H2"
    items, _ = build_items("agents", parsed.golden_queries, markdown=md)
    assert items[0].question == "Active agents per hub"
    assert "SELECT hub_name" in items[0].expected_query


# ---------------------------------------------------------------------------
# Scoping generation/pruning to selected stems
# ---------------------------------------------------------------------------

_METRIC_MD = "# T\n\n## Golden Queries\n\n### Query 1 — Monthly\n\n```sql\nSELECT 1\n```\n"
_AUTO_YAML = "# auto-generated\nitems: []\n"
_HAND_YAML = "items:\n- id: hand\n  question: q\n  expected_query: SELECT 1\n"


def _one_golden(text: str, fallback_title: str = ""):
    """Parser stub: every doc yields exactly one golden query."""
    return SimpleNamespace(
        golden_queries=[SimpleNamespace(name="Query 1 — Monthly", sql="SELECT 1")]
    )


def _make_tree(
    tmp_path: Path,
    *,
    docs: dict[str, str] | None = None,
    datasets: dict[str, str] | None = None,
) -> tuple[Path, Path]:
    """Build a repo-shaped tree; return ``(llm_context_dir, datasets_dir)``."""
    llm = tmp_path / "docs" / "llm_context"
    (llm / "metric_entities").mkdir(parents=True)
    for stem, body in (docs or {}).items():
        (llm / "metric_entities" / f"{stem}.md").write_text(body, encoding="utf-8")
    ds = tmp_path / "datasets"
    ds.mkdir()
    for stem, body in (datasets or {}).items():
        (ds / f"{stem}.yaml").write_text(body, encoding="utf-8")
    return llm, ds


def _generate(llm: Path, ds: Path, root: Path, **kwargs) -> int:
    return generate_datasets(
        llm_context_dir=llm,
        datasets_dir=ds,
        parse_markdown=_one_golden,
        repo_root=root,
        **kwargs,
    )


def test_scoped_run_ignores_out_of_scope_hand_authored_collision(tmp_path: Path):
    """The CI-blocking case: an untouched hand-authored dataset must not fail the run."""
    llm, ds = _make_tree(
        tmp_path,
        docs={"turnover": _METRIC_MD, "accounting": _METRIC_MD},
        datasets={"accounting": _HAND_YAML},
    )

    assert _generate(llm, ds, tmp_path) == 1, "full scan still fails on the collision"

    assert _generate(llm, ds, tmp_path, stems={"turnover"}) == 0
    assert (ds / "turnover.yaml").exists()
    assert (ds / "accounting.yaml").read_text(encoding="utf-8") == _HAND_YAML


def test_scoped_run_still_fails_on_in_scope_hand_authored_collision(tmp_path: Path):
    """A collision the diff actually caused is still a hard failure, with no writes."""
    llm, ds = _make_tree(
        tmp_path,
        docs={"turnover": _METRIC_MD, "accounting": _METRIC_MD},
        datasets={"accounting": _HAND_YAML},
    )

    assert _generate(llm, ds, tmp_path, stems={"turnover", "accounting"}) == 1
    assert (ds / "accounting.yaml").read_text(encoding="utf-8") == _HAND_YAML
    assert not (ds / "turnover.yaml").exists(), "fail-fast: no partial writes"


def test_skip_hand_authored_downgrades_in_scope_collision_to_a_skip(tmp_path: Path):
    """The drift check's case: editing a hand-authored dataset's doc must not fail.

    A hand-authored dataset is never regenerated, so it cannot drift from its
    source doc. Without this the author of such a doc edit would have no way to
    get their PR green.
    """
    llm, ds = _make_tree(
        tmp_path,
        docs={"turnover": _METRIC_MD, "accounting": _METRIC_MD},
        datasets={"accounting": _HAND_YAML},
    )

    rc = _generate(
        llm, ds, tmp_path, stems={"turnover", "accounting"}, skip_hand_authored=True
    )

    assert rc == 0
    assert (ds / "accounting.yaml").read_text(encoding="utf-8") == _HAND_YAML
    assert (ds / "turnover.yaml").exists(), "in-scope auto stems are still generated"


def test_skip_hand_authored_does_not_prune_the_skipped_dataset(tmp_path: Path):
    """A skipped hand-authored dataset must not then be swept up by the pruner."""
    llm, ds = _make_tree(
        tmp_path, docs={"accounting": _METRIC_MD}, datasets={"accounting": _HAND_YAML}
    )

    assert (
        _generate(llm, ds, tmp_path, stems={"accounting"}, skip_hand_authored=True) == 0
    )
    assert (ds / "accounting.yaml").read_text(encoding="utf-8") == _HAND_YAML


def test_skip_hand_authored_defaults_off(tmp_path: Path):
    """Normal generation still refuses to clobber curated expectations."""
    llm, ds = _make_tree(
        tmp_path, docs={"accounting": _METRIC_MD}, datasets={"accounting": _HAND_YAML}
    )

    assert _generate(llm, ds, tmp_path, stems={"accounting"}) == 1


def test_scoped_run_prunes_dataset_whose_doc_was_deleted(tmp_path: Path):
    """A deleted metric doc's orphaned auto-generated dataset is pruned when in scope."""
    llm, ds = _make_tree(tmp_path, docs={}, datasets={"gone": _AUTO_YAML})

    assert _generate(llm, ds, tmp_path, stems={"gone"}) == 0
    assert not (ds / "gone.yaml").exists()


def test_scoped_run_leaves_out_of_scope_orphans_alone(tmp_path: Path):
    """Pruning is scoped too — an orphan the diff never touched must survive."""
    llm, ds = _make_tree(
        tmp_path,
        docs={"turnover": _METRIC_MD},
        datasets={"turnover": _AUTO_YAML, "unrelated_orphan": _AUTO_YAML},
    )

    assert _generate(llm, ds, tmp_path, stems={"turnover"}) == 0
    assert (ds / "unrelated_orphan.yaml").exists()


def test_scoped_run_handles_rename_prune_old_write_new(tmp_path: Path):
    """A renamed doc: the new stem is written, the old stem's dataset pruned."""
    llm, ds = _make_tree(
        tmp_path,
        docs={"new_name": _METRIC_MD},
        datasets={"old_name": _AUTO_YAML},
    )

    assert _generate(llm, ds, tmp_path, stems={"new_name", "old_name"}) == 0
    assert (ds / "new_name.yaml").exists()
    assert not (ds / "old_name.yaml").exists()


def test_empty_scope_is_a_successful_noop(tmp_path: Path):
    """A PR touching no metric doc must neither write nor prune anything."""
    llm, ds = _make_tree(
        tmp_path,
        docs={"turnover": _METRIC_MD},
        datasets={"orphan": _AUTO_YAML},
    )

    assert _generate(llm, ds, tmp_path, stems=set()) == 0
    assert not (ds / "turnover.yaml").exists()
    assert (ds / "orphan.yaml").exists()


def test_none_scope_keeps_full_scan_behavior(tmp_path: Path):
    """Explicit ``stems=None`` is the pre-scoping full scan (regression guard)."""
    llm, ds = _make_tree(
        tmp_path,
        docs={"turnover": _METRIC_MD},
        datasets={"orphan": _AUTO_YAML},
    )

    assert _generate(llm, ds, tmp_path, stems=None) == 0
    assert (ds / "turnover.yaml").exists()
    assert not (ds / "orphan.yaml").exists()


def test_scoped_stem_with_neither_doc_nor_dataset_is_a_noop(tmp_path: Path):
    llm, ds = _make_tree(tmp_path, docs={"turnover": _METRIC_MD})

    assert _generate(llm, ds, tmp_path, stems={"never_existed"}) == 0
    assert list(ds.glob("*.yaml")) == []


def test_scoped_dry_run_writes_and_prunes_nothing(tmp_path: Path):
    llm, ds = _make_tree(
        tmp_path,
        docs={"turnover": _METRIC_MD},
        datasets={"stale": _AUTO_YAML},
    )

    assert _generate(llm, ds, tmp_path, stems={"turnover", "stale"}, dry_run=True) == 0
    assert not (ds / "turnover.yaml").exists()
    assert (ds / "stale.yaml").exists()


def test_scoped_run_reports_the_scope(tmp_path: Path, capsys):
    llm, ds = _make_tree(tmp_path, docs={"turnover": _METRIC_MD})

    _generate(llm, ds, tmp_path, stems={"turnover"})

    assert "scope: 1 stem(s) — turnover" in capsys.readouterr().out


def test_empty_scope_reports_the_noop(tmp_path: Path, capsys):
    llm, ds = _make_tree(tmp_path, docs={"turnover": _METRIC_MD})

    _generate(llm, ds, tmp_path, stems=set())

    assert "scope: empty" in capsys.readouterr().out


# --- parse_stems_file -------------------------------------------------------


def test_parse_stems_file_reads_one_stem_per_line():
    assert parse_stems_file("turnover\nnps_fr\n") == {"turnover", "nps_fr"}


def test_parse_stems_file_ignores_blanks_comments_and_whitespace():
    text = "\n  turnover  \n# a comment\n\nnps_fr  # trailing\n   \n"
    assert parse_stems_file(text) == {"turnover", "nps_fr"}


def test_parse_stems_file_empty_text_is_empty_set():
    assert parse_stems_file("") == set()


# --- resolve_selected_stems -------------------------------------------------


def test_resolve_selected_stems_none_when_no_flags_given():
    assert resolve_selected_stems(None, None) is None


def test_resolve_selected_stems_from_cli_flags():
    assert resolve_selected_stems(["turnover", "nps_fr"], None) == {"turnover", "nps_fr"}


def test_resolve_selected_stems_unions_cli_and_file(tmp_path: Path):
    path = tmp_path / "scope"
    path.write_text("nps_fr\nturnover\n", encoding="utf-8")

    assert resolve_selected_stems(["accounting"], path) == {
        "accounting",
        "nps_fr",
        "turnover",
    }


def test_resolve_selected_stems_empty_file_is_empty_scope_not_full_scan(tmp_path: Path):
    """An empty resolver output means "nothing changed", never "regenerate everything"."""
    path = tmp_path / "scope"
    path.write_text("", encoding="utf-8")

    assert resolve_selected_stems(None, path) == set()


def test_resolve_selected_stems_missing_file_raises(tmp_path: Path):
    with pytest.raises(OSError):
        resolve_selected_stems(None, tmp_path / "nope")


# --- CLI wiring -------------------------------------------------------------


def _stub_cli_environment(monkeypatch, tmp_path: Path) -> dict:
    """Capture generate_datasets kwargs instead of touching the real repo."""
    captured: dict = {}

    def fake_generate(**kwargs):
        captured.update(kwargs)
        return 0

    monkeypatch.setattr(gfc, "generate_datasets", fake_generate)
    monkeypatch.setattr(gfc, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        gfc,
        "load_document_parser",
        lambda: SimpleNamespace(parse_entity_markdown=_one_golden),
    )
    return captured


def test_main_defaults_to_unscoped_full_scan(monkeypatch, tmp_path: Path):
    captured = _stub_cli_environment(monkeypatch, tmp_path)

    assert gfc.main([]) == 0
    assert captured["stems"] is None


def test_main_collects_repeated_stem_flags(monkeypatch, tmp_path: Path):
    captured = _stub_cli_environment(monkeypatch, tmp_path)

    assert gfc.main(["--stem", "turnover", "--stem", "nps_fr"]) == 0
    assert captured["stems"] == {"turnover", "nps_fr"}


def test_main_reads_stems_file(monkeypatch, tmp_path: Path):
    captured = _stub_cli_environment(monkeypatch, tmp_path)
    path = tmp_path / "scope"
    path.write_text("turnover\nnps_fr\n", encoding="utf-8")

    assert gfc.main(["--stems-file", str(path)]) == 0
    assert captured["stems"] == {"turnover", "nps_fr"}


def test_main_empty_stems_file_scopes_to_nothing(monkeypatch, tmp_path: Path):
    captured = _stub_cli_environment(monkeypatch, tmp_path)
    path = tmp_path / "scope"
    path.write_text("", encoding="utf-8")

    assert gfc.main(["--stems-file", str(path)]) == 0
    assert captured["stems"] == set()


def test_main_unreadable_stems_file_exits_2(monkeypatch, tmp_path: Path, capsys):
    """Structural error — exit 2, matching the package's 1-vs-2 exit convention."""
    _stub_cli_environment(monkeypatch, tmp_path)

    assert gfc.main(["--stems-file", str(tmp_path / "nope")]) == 2
    assert "cannot read --stems-file" in capsys.readouterr().err


def test_main_defaults_skip_hand_authored_off(monkeypatch, tmp_path: Path):
    captured = _stub_cli_environment(monkeypatch, tmp_path)

    assert gfc.main([]) == 0
    assert captured["skip_hand_authored"] is False


def test_main_forwards_skip_hand_authored_flag(monkeypatch, tmp_path: Path):
    captured = _stub_cli_environment(monkeypatch, tmp_path)

    assert gfc.main(["--skip-hand-authored"]) == 0
    assert captured["skip_hand_authored"] is True
