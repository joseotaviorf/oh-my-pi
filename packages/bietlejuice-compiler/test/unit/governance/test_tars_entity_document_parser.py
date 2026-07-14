"""Unit tests for TARS entity document parser."""

from __future__ import annotations

import sys
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

SAMPLE_MD = """\
# Payments

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
    "## Overview\n\nNPS overview for For Rent.\n\n"
    "## Tables\n\nUse `dw_customer_satisfaction.fact_nps_dispatches`.\n\n"
    "## Golden Query\n\n"
    "\\`\\``sql WITH j AS ( SELECT 1 AS x "
    "FROM dw_customer_satisfaction.fact_nps_dispatches ) "
    "SELECT * FROM j ORDER BY x` \\`\\`\n\n"
    "## Dos and Don'ts\n\nDo things.\n"
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


def test_metric_document_skips_tables_and_golden_query_checks():
    # Metric docs are thin on schema: no ## Tables section and no golden query
    # required (calculation + canonical filter are the source of truth).
    metric_md = (
        "# NPS FR\n\n"
        "## Overview\n\nOfficial weighted NPS for For Rent.\n\n"
        "## Calculation\n\nWeighted sum of journey components.\n\n"
        "### Canonical Filter\n\n```sql\nbusiness_context = 'forRent'\n```\n"
    )
    parsed = parse_entity_markdown(metric_md)
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert errors == []
    assert warnings == []


def test_domain_document_still_requires_tables_and_golden_query():
    # Same thin content fails for a domain entity, which must route by table and
    # teach a canonical query.
    metric_md = "# NPS FR\n\n## Overview\n\nNPS overview.\n"
    parsed = parse_entity_markdown(metric_md)
    errors, _warnings = validate_parsed_document(parsed, data_product_type="domain")
    assert any("Golden Queries" in e for e in errors)
    assert any("schema.table" in e for e in errors)


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
