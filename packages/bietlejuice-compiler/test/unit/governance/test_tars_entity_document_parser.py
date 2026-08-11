"""Unit tests for TARS entity document parser."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[5]
_SYNC_DIR = _REPO_ROOT / "dags/governance/datahub_business_context"
if str(_SYNC_DIR) not in sys.path:
    sys.path.insert(0, str(_SYNC_DIR))

from sync.document_parser import (  # noqa: E402
    extract_subjects_from_sql,
    parse_entity_markdown,
    validate_parsed_document,
)

from scripts.ci_cd import generate_and_push_datahub_entities as g  # noqa: E402

SAMPLE_MD = """\
# Payments

## Ownership

**Data Owner:**
- owner@quintoandar.com.br

**Data Steward:**
- steward@quintoandar.com.br

## Overview

Payments tracks every charge processed through Checkout.

## Glossary and Synonyms

| Term | Meaning | Technical mapping |
|------|---------|-------------------|
| **Pagamento** | Payment | `dw_payments_platform.fact_payment` |

## Tables

| You need… | Use this table |
|-----------|----------------|
| Unified payment fact | `dw_payments_platform.fact_payment` |

## Dos and Don'ts

**Do:** filter on `is_valid = true`.

**Don't:** double-count refunds.

## Golden Queries

### Query 1 — Payment volume

Daily payment count by method.

```sql
SELECT
    date_trunc('day', ts_paid) AS dt_paid,
    payment_method,
    COUNT(*) AS payment_count
FROM dw_payments_platform.fact_payment
WHERE is_valid = true
GROUP BY 1, 2
ORDER BY 1 DESC;
```
"""


def test_parse_entity_markdown_extracts_sections():
    parsed = parse_entity_markdown(SAMPLE_MD)
    assert parsed.title == "Payments"
    assert "Checkout" in parsed.overview
    assert len(parsed.glossary_terms) == 1
    assert parsed.glossary_terms[0].term_id == "pagamento"
    assert ("dw_payments_platform", "fact_payment") in parsed.datasets
    assert len(parsed.golden_queries) == 1
    assert parsed.golden_queries[0].name.startswith("Query 1")


def test_validate_parsed_document_passes_for_complete_doc():
    parsed = parse_entity_markdown(SAMPLE_MD)
    errors, warnings = validate_parsed_document(parsed)
    assert errors == []
    assert warnings == []


def test_validate_parsed_document_fails_without_golden_query():
    parsed = parse_entity_markdown(
        "# Foo\n\n## Overview\n\nBar\n\n## Tables\n\n`dw_a.fact_b`\n"
    )
    errors, _warnings = validate_parsed_document(parsed)
    assert any("Golden Queries" in e for e in errors)


# DataHub's rich-text editor stores fenced SQL inline on one line (no newline
# after ```sql), backslash-escapes the backticks, and splits the closing fence
# with a space (``` -> ` ``). This is exactly how a published document reaches
# the audit task, so the parser must still find the golden query.
DATAHUB_INLINE_MD = (
    "# Testing NPS 2\n\n"
    "## Ownership\n\n**Data Owner:**\n- owner@quintoandar.com.br\n\n"
    "**Data Steward:**\n- steward@quintoandar.com.br\n\n"
    "## Overview\n\nNPS overview for For Rent.\n\n"
    "## Glossary and Synonyms\n\n- **NPS** → net promoter score\n\n"
    "## Tables\n\nUse `dw_customer_satisfaction.fact_nps_dispatches`.\n\n"
    "## Golden Query\n\n"
    "\\`\\``sql WITH j AS ( SELECT 1 AS x "
    "FROM dw_customer_satisfaction.fact_nps_dispatches ) "
    "SELECT * FROM j ORDER BY x` \\`\\`\n\n"
    "## Dos and Don'ts\n\n**Do:** things.\n\n**Don't:** other things.\n"
)


def test_parse_inline_datahub_fence_extracts_golden_query():
    parsed = parse_entity_markdown(DATAHUB_INLINE_MD, fallback_title="Testing NPS 2")
    assert len(parsed.golden_queries) == 1
    sql = parsed.golden_queries[0].sql
    assert sql.startswith("WITH j AS")
    assert "```" not in sql and "`" not in sql  # no fence remnants leak into the SQL
    errors, warnings = validate_parsed_document(parsed)
    assert errors == []
    assert warnings == []


def test_metric_document_skips_tables_but_requires_documented_sections():
    # Metric docs are thin on schema: no ## Tables section required, but they must
    # carry the full documented authoring set (ownership, scope, golden query, …).
    metric_md = (
        "# NPS FR\n\n"
        "## Ownership\n\n"
        "**Data Owner:**\n- owner@quintoandar.com.br\n\n"
        "**Data Steward:**\n- steward@quintoandar.com.br\n\n"
        "## Overview\n\nOfficial weighted NPS for For Rent.\n\n"
        "## Related Business Entities\n\n- NPS\n\n"
        "## Glossary and Synonyms\n\n- **NPS FR** → this metric\n\n"
        "## Scope\n\n**Included**: For Rent journeys\n\n**Excluded**: test campaigns\n\n"
        "## Calculation\n\nWeighted sum of journey components.\n\n"
        "### Canonical Filter\n\n```sql\nbusiness_context = 'forRent'\n```\n\n"
        "## Dos and Don'ts\n\n**Do:**\n\n- apply the canonical filter\n\n"
        "**Don't:**\n\n- pool components directly\n\n"
        "## Golden Queries\n\n"
        "```sql\nSELECT journey, weighted_nps FROM dw.nps_fr\n```\n"
    )
    parsed = parse_entity_markdown(metric_md)
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert errors == []
    assert warnings == []
    assert ("dw", "nps_fr") not in parsed.datasets  # no ## Tables gate for metrics


def test_domain_document_still_requires_tables_and_golden_query():
    # Same thin content fails for a domain entity, which must route by table and
    # teach a canonical query.
    metric_md = "# NPS FR\n\n## Overview\n\nNPS overview.\n"
    parsed = parse_entity_markdown(metric_md)
    errors, _warnings = validate_parsed_document(parsed, data_product_type="domain")
    assert any("Golden Queries" in e for e in errors)
    assert any("schema.table" in e for e in errors)


def test_domain_document_requires_ownership():
    # Ownership (Data Owner + Steward) is now required for domain entities too,
    # in lockstep with Zordon's dp_validator — mirrors the metric gate.
    domain_md = (
        "# Payments\n\n## Overview\n\nx\n\n"
        "## Tables\n\n`dw_a.fact_b`\n\n"
        "## Golden Queries\n\n```sql\nSELECT 1 FROM dw_a.fact_b\n```\n"
    )
    parsed = parse_entity_markdown(domain_md)
    errors, _ = validate_parsed_document(parsed, data_product_type="domain")
    assert "Missing ## Ownership section" in errors


def test_domain_document_requires_glossary_and_dos_and_donts():
    # Parity with metric: the shared content sections (Glossary, Dos and Don'ts) are
    # now required for domain entities too — only the type-specific sections differ.
    domain_md = (
        "# Payments\n\n"
        "## Ownership\n\n**Data Owner:**\n- a@quintoandar.com.br\n\n"
        "**Data Steward:**\n- b@quintoandar.com.br\n\n"
        "## Overview\n\nx\n\n"
        "## Tables\n\n`dw_a.fact_b`\n\n"
        "## Golden Queries\n\n```sql\nSELECT 1 FROM dw_a.fact_b\n```\n"
    )
    parsed = parse_entity_markdown(domain_md)
    errors, _ = validate_parsed_document(parsed, data_product_type="domain")
    assert any("Glossary" in e for e in errors)
    assert any("Dos and Don" in e for e in errors)


def test_extract_subjects_from_sql():
    sql = """
    SELECT a.x
    FROM dw_payments_platform.fact_payment AS a
    JOIN dw_payments_platform.dim_method AS b
      ON a.sk_method = b.sk_method
    """
    subjects = extract_subjects_from_sql(sql)
    assert ("dw_payments_platform", "fact_payment") in subjects
    assert ("dw_payments_platform", "dim_method") in subjects


INLINE_GOLDEN_H3_MD = """\
# Ongoing Listings (Daily Volume)

## Overview

Daily published inventory.

## For Rent (RENT)

### Canonical filter (RENT)

```sql
fhls.status_history IN ('publicado', 'PUBLISHED')
```

### Golden Query — RENT daily volume

```sql
SELECT COUNT(DISTINCT sk_house_listing) AS ongoing_listings
FROM dw_rent.fact_house_listing_status
WHERE status_history IN ('publicado', 'PUBLISHED')
```

## For Sale (SALE)

### Golden Query — SALE daily volume

```sql
SELECT COUNT(DISTINCT sk_sale_listing) AS ongoing_listings
FROM dw_sale.fact_daily_ongoing_listing
```
"""


def test_inline_golden_query_h3_without_golden_queries_section_agrees_with_publisher():
    """Regression: an H3 "Golden Query — ..." nested under an arbitrary segment H2
    (no ## Golden Queries heading anywhere) must NOT be picked up by
    ``parse_entity_markdown`` — ``generate_and_push_datahub_entities.py`` never
    opens a golden-query zone on an H3 under an unrelated parent, only on an H2
    (``_GOLDEN_QUERY_SINGULAR_HEADING_RE`` / ``_GOLDEN_QUERY_SECTION_HEADING_RE``).
    Asserts both sides agree (0 queries), so a doc shaped like this can't pass CI
    validation while silently publishing zero golden queries.
    """
    parsed = parse_entity_markdown(INLINE_GOLDEN_H3_MD)
    assert parsed.golden_queries == []

    tmp_dir = Path(tempfile.mkdtemp())
    md_path = tmp_dir / "demo.md"
    md_path.write_text(INLINE_GOLDEN_H3_MD, encoding="utf-8")
    assert g._count_expected_golden_queries(md_path) == 0
    assert g._extract_golden_query_sqls(md_path) == []
    md_path.unlink()
    tmp_dir.rmdir()


INLINE_GOLDEN_H2_MD = """\
# Ongoing Listings (Daily Volume)

## Overview

Daily published inventory.

## Golden query: RENT daily volume

```sql
SELECT COUNT(DISTINCT sk_house_listing) AS ongoing_listings
FROM dw_rent.fact_house_listing_status
WHERE status_history IN ('publicado', 'PUBLISHED')
```
"""


def test_standalone_h2_golden_query_heading_agrees_with_publisher():
    """The legitimately-supported inline pattern: a standalone H2
    ``## Golden query: {Name}`` heading instead of a ``## Golden Queries``
    section — exactly the shape ``_GOLDEN_QUERY_SINGULAR_HEADING_RE`` requires in
    the publisher, so both sides must agree on what counts as a golden query here.
    """
    parsed = parse_entity_markdown(INLINE_GOLDEN_H2_MD)
    assert len(parsed.golden_queries) == 1
    assert "dw_rent.fact_house_listing_status" in parsed.golden_queries[0].sql

    tmp_dir = Path(tempfile.mkdtemp())
    md_path = tmp_dir / "demo.md"
    md_path.write_text(INLINE_GOLDEN_H2_MD, encoding="utf-8")
    assert g._count_expected_golden_queries(md_path) == len(parsed.golden_queries)
    assert g._extract_golden_query_sqls(md_path) == [
        q.sql for q in parsed.golden_queries
    ]
    md_path.unlink()
    tmp_dir.rmdir()


def test_standard_golden_queries_section_not_double_counted():
    parsed = parse_entity_markdown(SAMPLE_MD)
    assert len(parsed.golden_queries) == 1
    assert parsed.golden_queries[0].name.startswith("Query 1")
    assert "dw_payments_platform.fact_payment" in parsed.golden_queries[0].sql
