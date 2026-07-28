"""Tests for the deterministic DataHub context-entity CI validator.

Focus on the blocking behavior of the offline gate: what makes a hand-authored
entity ``.md`` pass vs. fail. Warnings (e.g. filename casing) are non-blocking by
design and are asserted to NOT appear in the error list.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest
from validate_datahub_context_entities import (
    _data_product_type,
    _filter_entity_paths,
    _is_entity_md,
    _maybe_comment_on_pr,
    _maybe_comment_success,
    _pr_comment_body,
    _static_checks,
    _validate_file,
    main,
)


@pytest.fixture(autouse=True)
def _never_post_to_a_real_pr(monkeypatch):
    """Hermetic by default: clear the PR-number env so ``main()`` never tries to post
    a comment to the real PR during tests (CI runs on a pull_request, where it's set).
    Tests that exercise the posting path set it back explicitly."""
    monkeypatch.delenv("CI_COMMIT_PULL_REQUEST", raising=False)


_VALID_METRIC = """\
# My Metric

## Ownership

**Data Owner:**
- owner@quintoandar.com.br

**Data Steward:**
- steward@quintoandar.com.br

## Overview

My Metric is the official indicator for something, computed monthly.

## Related Business Entities

- Contact

## Glossary and Synonyms

- **My Metric** → this metric

## Scope

**Included**: everything relevant.

**Excluded**: test data.

## Calculation

My Metric = numerator / denominator.

## Dos and Don'ts

**Do:**

- Use the canonical filter.

**Don't:**

- Don't hardcode weights.

## Golden Queries

```sql
SELECT count(*) FROM schema.my_table
```
"""

_VALID_DOMAIN = """\
# My Domain

## Ownership

**Data Owner:**
- owner@quintoandar.com.br

**Data Steward:**
- steward@quintoandar.com.br

## Overview

Business context for the domain.

## Glossary and Synonyms

- **termo** → maps to something

## Tables

The canonical table is `schema.my_table`.

## Dos and Don'ts

**Do:** use the canonical table.

**Don't:** query raw sources.

## Golden Queries

```sql
SELECT count(*) FROM schema.my_table
```
"""


def _write(dir_: Path, subdir: str, name: str, content: str) -> Path:
    d = dir_ / subdir
    d.mkdir(parents=True, exist_ok=True)
    p = d / name
    p.write_text(content, encoding="utf-8")
    return p


# ── routing / filtering ────────────────────────────────────────────────────────


def test_data_product_type_routes_by_directory(tmp_path: Path):
    metric = _write(tmp_path / "llm_context", "metric_entities", "m.md", _VALID_METRIC)
    domain = _write(
        tmp_path / "llm_context", "business_entities", "d.md", _VALID_DOMAIN
    )
    assert _data_product_type(metric) == "metric"
    assert _data_product_type(domain) == "domain"


def test_template_and_non_entity_files_filtered_out(tmp_path: Path):
    tpl = _write(tmp_path / "llm_context", "metric_entities", "_TEMPLATE.md", "# x")
    other = tmp_path / "README.md"
    other.write_text("# x", encoding="utf-8")
    assert not _is_entity_md(tpl)  # leading underscore
    assert _filter_entity_paths([tpl, other]) == []


# ── valid docs pass ─────────────────────────────────────────────────────────────


def test_valid_metric_doc_has_no_errors(tmp_path: Path):
    p = _write(
        tmp_path / "llm_context", "metric_entities", "my_metric.md", _VALID_METRIC
    )
    errors, _ = _validate_file(p)
    assert errors == []


def test_valid_domain_doc_has_no_errors(tmp_path: Path):
    p = _write(
        tmp_path / "llm_context", "business_entities", "my_domain.md", _VALID_DOMAIN
    )
    errors, _ = _validate_file(p)
    assert errors == []


# ── structural failures (reused validate_parsed_document) ───────────────────────


def test_missing_h1_and_overview_are_errors(tmp_path: Path):
    p = _write(
        tmp_path / "llm_context",
        "metric_entities",
        "m.md",
        "Just prose, no headings.\n",
    )
    errors, _ = _validate_file(p)
    assert any("H1 title" in e for e in errors)
    assert any("Overview" in e for e in errors)


def test_domain_requires_tables_and_golden_queries(tmp_path: Path):
    md = "# D\n\n## Overview\n\ncontext only, no tables or queries\n"
    p = _write(tmp_path / "llm_context", "business_entities", "d.md", md)
    errors, _ = _validate_file(p)
    assert any("Tables" in e for e in errors)
    assert any("Golden Queries" in e for e in errors)


def test_metric_ownership_requires_owner_and_steward(tmp_path: Path):
    md = "# M\n\n## Overview\n\nx\n\n## Ownership\n\nno emails here\n"
    p = _write(tmp_path / "llm_context", "metric_entities", "m.md", md)
    errors, _ = _validate_file(p)
    assert any("Data Owner" in e for e in errors)
    assert any("Data Steward" in e for e in errors)


# ── static checks ───────────────────────────────────────────────────────────────


def test_placeholder_left_in_document_is_error(tmp_path: Path):
    errors, _ = _static_checks(
        Path("m.md"),
        "# M\n\n## Overview\n\nOwner: {data_owner_email@quintoandar.com.br}\n",
    )
    assert any("placeholder" in e.lower() for e in errors)


def test_writing_guide_block_is_error(tmp_path: Path):
    errors, _ = _static_checks(
        Path("m.md"), "<!--\nWRITING GUIDE — delete this block.\n-->\n# M\n"
    )
    assert any("WRITING GUIDE" in e for e in errors)


def test_placeholder_inside_code_block_is_ignored(tmp_path: Path):
    # Braces inside a fenced code block must not trip the placeholder check.
    content = "# M\n\n```sql\nSELECT {not_a_placeholder}\n```\n"
    errors, _ = _static_checks(Path("m.md"), content)
    assert not any("placeholder" in e.lower() for e in errors)


def test_filename_casing_is_warning_not_error(tmp_path: Path):
    errors, warnings = _static_checks(Path("Bad-Name.md"), "# M\n\n## Overview\n\nx\n")
    assert not any("snake_case" in e for e in errors)
    assert any("snake_case" in w for w in warnings)


def test_inline_html_comment_is_allowed(tmp_path: Path):
    # Only the template's WRITING GUIDE block is blocked; an ordinary inline
    # comment (as some merged docs carry) must not fail the gate.
    errors, _ = _static_checks(
        Path("m.md"), "# M\n<!-- a normal note -->\n## Overview\nx\n"
    )
    assert errors == []


# ── run output (main) ────────────────────────────────────────────────────────


def test_output_labels_type_and_points_to_template_on_failure(tmp_path, capsys):
    good = _write(
        tmp_path / "llm_context", "metric_entities", "good_metric.md", _VALID_METRIC
    )
    bad = _write(
        tmp_path / "llm_context",
        "metric_entities",
        "bad_metric.md",
        "# Bad\n\n## Overview\n\nincomplete\n",
    )
    rc = main(["--paths", str(good), str(bad)])
    combined = "".join(capsys.readouterr())

    assert rc == 1  # the bad doc fails the run
    assert "Scope" in combined  # scope is spelled out
    assert "(metric)" in combined  # the applied contract type is labelled
    # a failing doc points the author at the matching template
    assert "metric_entities/_TEMPLATE.md" in combined
    assert "see the template" in combined


def test_output_recaps_non_blocking_warnings(tmp_path, capsys):
    # A non-snake_case filename warns (non-blocking); the run still passes and the
    # footer recaps the warning count.
    good = _write(
        tmp_path / "llm_context", "metric_entities", "Brand-New.md", _VALID_METRIC
    )
    rc = main(["--paths", str(good)])
    combined = "".join(capsys.readouterr())

    assert rc == 0
    assert "non-blocking" in combined


def test_pr_comment_body_lists_each_failing_doc():
    body = _pr_comment_body(
        [
            (
                "docs/llm_context/metric_entities/x.md",
                "metric",
                [
                    "The `## Scope` section is missing or empty.",
                    "Missing ## Golden Queries",
                ],
            ),
        ]
    )
    assert "x.md" in body and "(metric)" in body
    assert "- The `## Scope` section is missing or empty." in body
    assert "- Missing ## Golden Queries" in body


def test_maybe_comment_posts_on_a_luigi_pr(monkeypatch):
    monkeypatch.setenv("CI_COMMIT_PULL_REQUEST", "42")
    monkeypatch.setenv("CI_COMMIT_SOURCE_BRANCH", "luigi/data-product/ticket-rate")
    with patch("sync.pr_comment.post_validation_failure", return_value=True) as post:
        _maybe_comment_on_pr([("x.md", "metric", ["e1"])])
    post.assert_called_once()
    assert post.call_args.args[0] == "42"


def test_maybe_comment_is_a_noop_off_a_pr(monkeypatch):
    monkeypatch.delenv("CI_COMMIT_PULL_REQUEST", raising=False)
    with patch("sync.pr_comment.post_validation_failure") as post:
        _maybe_comment_on_pr([("x.md", "metric", ["e1"])])
    post.assert_not_called()


def test_maybe_comment_is_a_noop_on_a_non_luigi_pr(monkeypatch):
    # A regular engineer's entity-doc PR (not a luigi/data-product/* branch) gets no
    # bot comment — they watch CI themselves.
    monkeypatch.setenv("CI_COMMIT_PULL_REQUEST", "42")
    monkeypatch.setenv("CI_COMMIT_SOURCE_BRANCH", "feat/some-engineer-change")
    monkeypatch.delenv("CI_COMMIT_BRANCH", raising=False)
    with patch("sync.pr_comment.post_validation_failure") as post:
        _maybe_comment_on_pr([("x.md", "metric", ["e1"])])
    post.assert_not_called()


def test_maybe_comment_success_posts_on_every_luigi_pr_pass(monkeypatch):
    monkeypatch.setenv("CI_COMMIT_PULL_REQUEST", "42")
    monkeypatch.setenv("CI_COMMIT_SOURCE_BRANCH", "luigi/data-product/ticket-rate")
    with patch("sync.pr_comment.post_validation_success", return_value=True) as done:
        _maybe_comment_success()
    done.assert_called_once_with("42")


def test_maybe_comment_success_is_a_noop_off_a_pr(monkeypatch):
    monkeypatch.delenv("CI_COMMIT_PULL_REQUEST", raising=False)
    with patch("sync.pr_comment.post_validation_success") as done:
        _maybe_comment_success()
    done.assert_not_called()
