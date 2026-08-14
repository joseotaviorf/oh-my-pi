"""Regression tests for document_parser — DataHub rich-text export artifacts.

The fixture below is the exact Ownership/Glossary shape DataHub's "Create
Document" editor produced for a real Context Document (Property Integrity
metric entity, before the markdown_sanitizer fix): role headings and bullet
items glued onto a single physical line, with redundant ``***_..._***``
emphasis.
"""

from __future__ import annotations

import pytest

from sync.document_parser import parse_entity_markdown, validate_parsed_document
from sync.markdown_sanitizer import sanitize_uploaded_markdown

# A metric doc carrying every section the template/skill document as required.
# Tests that check a specific missing section omit exactly one part from this set.
_METRIC_PARTS = [
    (
        "## Ownership",
        "**Data Owner:**\n- owner@quintoandar.com.br\n\n"
        "**Data Steward:**\n- steward@quintoandar.com.br",
    ),
    ("## Overview", "What it measures and why the naive path is wrong."),
    ("## Related Business Entities", "- Contact"),
    (
        "## Catalog",
        "| Metric | Type |\n| :---- | :---- |\n| My Metric | OKR |",
    ),
    ("## Glossary and Synonyms", "- **My Metric** → this metric"),
    ("## Scope", "**Included**: x\n\n**Excluded**: y"),
    (
        "## Calculation",
        "Metric = a / b\n\n### Canonical Filter\n\n`where is_current = true`\n\n"
        "### Nuances\n\nMind the denominator.",
    ),
    ("## Dos and Don'ts", "**Do:**\n\n- do this\n\n**Don't:**\n\n- not that"),
    ("## Golden Queries", "```sql\nSELECT count(*) FROM dw.my_table\n```"),
]


def _metric_doc(omit: str | None = None) -> str:
    """A complete metric doc, optionally omitting one ``## Heading`` section."""
    out = "# My Metric\n\n"
    for heading, content in _METRIC_PARTS:
        if heading == omit:
            continue
        out += f"{heading}\n\n{content}\n\n"
    return out


def test_unescape_false_keeps_author_backslashes():
    # A hand-uploaded (Luigi) file is never DataHub-escaped; unescape=False must
    # leave the author's literal backslash intact instead of stripping it.
    md = "# T\n\n## Overview\nField named 50\\_pct here.\n"
    parsed = parse_entity_markdown(
        md, unescape=False, sanitize_fn=sanitize_uploaded_markdown
    )
    assert "50\\_pct" in parsed.raw_markdown


def test_default_unescape_true_still_strips_datahub_escapes():
    # Default behavior (DataHub source) is unchanged: backslash-escapes removed.
    md = "# T\n\n## Overview\nField named 50\\_pct here.\n"
    parsed = parse_entity_markdown(md)
    assert "50_pct" in parsed.raw_markdown
    assert "50\\_pct" not in parsed.raw_markdown


_GARBLED_DOC = """\
# **<span style="font-size:12px">Property Integrity</span>**

## **Ownership**

***_Data Owner:_***- [carolina.espinoza@quintoandar.com.br](mailto:carolina.espinoza@quintoandar.com.br)- [felipe.abreu@quintoandar.com.br](mailto:felipe.abreu@quintoandar.com.br)
***_Data Steward:_***- [victor.prado@quintoandar.com.br](mailto:victor.prado@quintoandar.com.br)

## **Overview**

***_Property Integrity_*** is a family of offboarding-quality metrics for the For Rent product.

## MBR

- Post Contract
"""


def test_owners_are_recovered_from_glued_datahub_export():
    parsed = parse_entity_markdown(_GARBLED_DOC)
    assert parsed.owners["data_owner"] == [
        "carolina.espinoza@quintoandar.com.br",
        "felipe.abreu@quintoandar.com.br",
    ]
    assert parsed.owners["data_steward"] == ["victor.prado@quintoandar.com.br"]
    assert parsed.mbr == [{"name": "Post Contract"}]


def test_sanitizes_bold_italic_underscore_when_underscores_are_backslash_escaped():
    """Regression: DataHub backslash-escapes underscores but not the bold
    asterisks around them (``**\\_Data Owner:\\_**``), producing a heading the
    markdown_sanitizer's emphasis regexes can't match until the escaping
    backslash is stripped. Sanitizing before unescaping left this artifact in
    the committed markdown (``raw_markdown`` / ``build_markdown_file`` output)
    even though owners still parsed correctly from the same text — see the
    'Cases Perspective' Context Document sync that surfaced this.
    """
    doc = (
        "# Metric Entity: Cases Perspective\n\n"
        "## Ownership\n\n"
        "**\\_Data Owner:\\_**\n\n"
        "- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)\n\n"
        "## Overview\n\nBody.\n"
    )
    parsed = parse_entity_markdown(doc)
    assert parsed.owners["data_owner"] == ["joao.mariani@quintoandar.com.br"]
    assert "**Data Owner:**" in parsed.raw_markdown
    assert "**_Data Owner:_**" not in parsed.raw_markdown


def test_mbr_parsed_from_bold_wrapped_heading():
    doc = """\
# Metric

## **MBR**

- Post Contract
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.mbr == [{"name": "Post Contract"}]


def test_mbr_parsed_from_plain_line_without_bullet():
    doc = """\
# Metric

## **MBR**

Post Contract
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.mbr == [{"name": "Post Contract"}]


def test_mbr_parsed_from_name_and_category_pair():
    doc = """\
# Metric

## MBR

**Name** Post Contract
**Category** Quality
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.mbr == [{"name": "Post Contract", "category": "Quality"}]


def test_mbr_category_placeholder_is_dropped():
    doc = """\
# Metric

## MBR

**Name** Post Contract
**Category** {category}
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.mbr == [{"name": "Post Contract"}]


def test_catalog_parsed_into_metric_and_type_rows():
    doc = """\
# Metric

## Catalog

| Metric | Type |
| :---- | :---- |
| NPS True | OKR |
| NPS Onboarding | health metric |
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.catalog == [
        {"name": "NPS True", "type": "OKR"},
        {"name": "NPS Onboarding", "type": "Health Metric"},
    ]


def test_catalog_keeps_escaped_pipe_in_metric_name():
    """``EC|ES2CS`` is a real metric name; Markdown escapes its pipe as ``\\|``."""
    doc = """\
# Metric

## Catalog

| Metric | Type |
| :---- | :---- |
| EC\\|ES2CS | OKR |
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.catalog == [{"name": "EC|ES2CS", "type": "OKR"}]


def test_catalog_ignores_datahub_catalog_section():
    """``## DataHub Catalog`` is a tooling pointer, not the metric catalog."""
    doc = """\
# Metric

## DataHub Catalog

| Metric | Type |
| :---- | :---- |
| Stray | OKR |
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.catalog == []


def test_title_has_no_html_or_style_leakage():
    # Also covers the whole-heading-bold-wrap rule: house style is that a
    # DataHub Data Product's plain-text name field never carries the source
    # heading's "**" — only the heading *level* signals emphasis.
    parsed = parse_entity_markdown(_GARBLED_DOC)
    assert parsed.title == "Property Integrity"
    assert "<span" not in parsed.raw_markdown
    assert "font-size" not in parsed.raw_markdown


def test_glossary_multibold_synonyms_parsed_like_nps_fr():
    doc = """\
# NPS FR

## Overview

Official weighted NPS.

## Glossary and Synonyms

- **NPS FR**, **NPS True**, **official NPS**, **weighted NPS** → NPS True (weighted average of the journeys)
- **NPS Onboarding**, **NPS Ongoing** → single-journey component
"""
    parsed = parse_entity_markdown(doc)
    assert len(parsed.glossary_terms) == 2
    assert parsed.glossary_terms[0].term_id == "nps_fr"
    assert parsed.glossary_terms[0].name == (
        "NPS FR (NPS True, official NPS, weighted NPS)"
    )
    assert parsed.glossary_terms[0].description == (
        "NPS True (weighted average of the journeys)"
    )
    assert parsed.glossary_terms[1].term_id == "nps_onboarding"
    assert parsed.glossary_terms[1].name == "NPS Onboarding (NPS Ongoing)"


def test_glossary_glued_line_split_by_sanitizer():
    doc = """\
# Property Integrity

## Overview

Metric family.

## Glossary and Synonyms

- **Property Integrity**, **integridade** → this family- **% Offb. W/o Mediation** → % Offb. W/o Mediation
"""
    parsed = parse_entity_markdown(doc)
    assert len(parsed.glossary_terms) == 2
    assert parsed.glossary_terms[0].term_id == "property_integrity"
    assert parsed.glossary_terms[1].term_id == "offb_w_o_mediation"


def test_related_business_entities_parsed_to_product_ids():
    doc = """\
# Metric

## Overview

Body.

## Related Business Entities

- NPS
- House and Listing
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.related_data_products == ["nps", "house-and-listing"]
    assert parsed.has_related_business_entities_section is True


def test_related_business_entities_html_comment_is_not_an_entity():
    # Regression: ``<!-- optional -->`` slugifies to ``optional`` if comments are
    # not stripped, so CI would accept a template leftover as a related product.
    parsed = parse_entity_markdown(
        _metric_doc().replace("- Contact", "<!-- optional -->")
    )
    assert parsed.has_related_business_entities_section is True
    assert parsed.related_data_products == []
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any("no entities were parsed" in e for e in errors)


def test_related_business_entities_keeps_bullets_beside_html_comments():
    parsed = parse_entity_markdown(
        _metric_doc().replace(
            "- Contact", "- House and Listing\n<!-- template hint -->"
        )
    )
    assert parsed.related_data_products == ["house-and-listing"]
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert not any("Related Business Entities" in e for e in errors)


def test_superset_golden_assets_parsed_for_metric_datasets():
    dataset_urn = "urn:li:dataset:(urn:li:dataPlatform:superset,16266,PROD)"
    chart_urn = "urn:li:chart:(superset,chart.56400)"
    dashboard_urn = "urn:li:dashboard:(superset,dashboard.123)"
    doc = f"""\
# NPS FR

## Overview

Body.

## Superset Golden Assets

- **Dataset** — `sandbox.nps_fr` — URN: `{dataset_urn}`
- **Chart** — URN: `{chart_urn}`
- **Dashboard** — URN: `{dashboard_urn}`
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.metric_dataset_rows == [
        {"schema": "sandbox", "table": "nps_fr"},
        {"urn": dataset_urn},
        {"urn": chart_urn},
        {"urn": dashboard_urn},
    ]
    assert parsed.datasets == []


def test_metric_validation_requires_owners_when_section_present():
    doc = """\
# Metric

## Ownership

**Data Owner:**
- owner@quintoandar.com.br

## Overview

Body.
"""
    parsed = parse_entity_markdown(doc)
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert any("Data Steward" in err for err in errors)
    assert warnings == []


def test_pre_ownership_heading_does_not_force_owner_validation():
    """Substring false positive: ``## Pre-ownership`` must not look like Ownership."""
    doc = """\
# Metric

## Overview

Body.

## Pre-ownership

Notes about ownership handoff — not the Ownership section.
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.has_ownership_section is False
    assert parsed.owners == {"data_owner": [], "data_steward": []}
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    # The section is genuinely absent → flagged as a missing SECTION; the
    # ``## Pre-ownership`` heading must NOT trigger the owner/steward EMAIL checks
    # (those only run when a real Ownership section is present).
    assert "Missing ## Ownership section" in errors
    assert not any("email in ## Ownership" in e for e in errors)


def test_ownership_still_found_after_pre_ownership_heading():
    doc = """\
# Metric

## Overview

Body.

## Pre-ownership

Handoff notes.

## **Ownership**

**Data Owner:**
- owner@quintoandar.com.br
**Data Steward:**
- steward@quintoandar.com.br
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.has_ownership_section is True
    assert parsed.owners["data_owner"] == ["owner@quintoandar.com.br"]
    assert parsed.owners["data_steward"] == ["steward@quintoandar.com.br"]
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    # Ownership parsed correctly → no ownership-related error (other sections are
    # absent in this minimal doc, so they error separately — not this test's concern).
    assert not any("Ownership" in e for e in errors)


def test_owners_accept_quintoandar_com_and_com_br():
    doc = """\
# Metric

## Ownership

**Data Owner:**
- owner@quintoandar.com

**Data Steward:**
- steward@quintoandar.com.br

## Overview

Body.
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.owners["data_owner"] == ["owner@quintoandar.com"]
    assert parsed.owners["data_steward"] == ["steward@quintoandar.com.br"]
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert not any("Ownership" in e for e in errors)


def test_metric_validation_errors_when_related_section_unparsed():
    doc = """\
# Metric

## Overview

Body.

## Related Business Entities


"""
    parsed = parse_entity_markdown(doc)
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert any("Related Business Entities" in err for err in errors)
    assert not any("Related Business Entities" in warn for warn in warnings)


def test_calculation_without_canonical_filter_or_nuances_is_blocking():
    doc = _metric_doc().replace(
        "### Canonical Filter\n\n`where is_current = true`\n\n"
        "### Nuances\n\nMind the denominator.",
        "Just the formula.",
    )
    errors, warnings = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Canonical Filter" in e for e in errors)
    assert any("Nuances" in e for e in errors)
    assert not any("Canonical Filter" in w for w in warnings)


def test_calculation_with_empty_canonical_filter_or_nuances_is_blocking():
    doc = _metric_doc().replace(
        "### Canonical Filter\n\n`where is_current = true`\n\n"
        "### Nuances\n\nMind the denominator.",
        "### Canonical Filter\n\n\n### Nuances\n\n",
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Canonical Filter" in e for e in errors)
    assert any("Nuances" in e for e in errors)


def test_empty_optional_mbr_section_is_blocking():
    doc = _metric_doc() + "\n## MBR\n\n"
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("mbr" in e.lower() and "empty" in e.lower() for e in errors)


def test_optional_mbr_with_html_comment_only_is_blocking():
    doc = _metric_doc() + "\n## MBR\n\n<!-- [OPTIONAL] Monthly business review -->\n"
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("mbr" in e.lower() and "empty" in e.lower() for e in errors)


def test_golden_queries_not_stolen_by_superset_section():
    doc = _metric_doc().replace(
        "## Golden Queries",
        "## Superset Golden Assets\n\nNo SQL here.\n\n## Golden Queries",
    )
    parsed = parse_entity_markdown(doc)
    assert len(parsed.golden_queries) == 1
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert not any("Golden Queries" in e for e in errors)


def test_catalog_missing_or_invalid_type_is_blocking():
    doc = _metric_doc(omit="## Catalog")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Catalog" in e for e in errors)

    doc_invalid = _metric_doc().replace("| My Metric | OKR |", "| My Metric | TBD |")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc_invalid), data_product_type="metric"
    )
    assert any("valid Type" in e for e in errors)


def test_catalog_escaped_pipe_parses_correctly():
    doc = _metric_doc().replace("| My Metric | OKR |", "| EC\\|ES2CS | OKR |")
    parsed = parse_entity_markdown(doc)
    assert parsed.catalog == [{"name": "EC|ES2CS", "type": "OKR"}]
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert not any("Catalog" in e for e in errors)


def test_catalog_skips_metric_name_header_row():
    doc = _metric_doc().replace(
        "| Metric | Type |\n| :---- | :---- |\n| My Metric | OKR |",
        "| Metric Name | Type |\n| :---- | :---- |\n| My Metric | OKR |",
    )
    parsed = parse_entity_markdown(doc)
    assert parsed.catalog == [{"name": "My Metric", "type": "OKR"}]


def test_catalog_accepts_health_metric_aliases():
    for alias in ("health-metric", "health metrics", "OKRs"):
        expected = "OKR" if alias == "OKRs" else "Health Metric"
        doc = _metric_doc().replace("| My Metric | OKR |", f"| My Metric | {alias} |")
        parsed = parse_entity_markdown(doc)
        assert parsed.catalog[0]["type"] == expected


def test_complete_metric_doc_passes():
    parsed = parse_entity_markdown(_metric_doc())
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert errors == []
    assert warnings == []


def test_scope_without_included_or_excluded_warns_not_blocks():
    # Present + non-empty → no error; the finer Included/Excluded rule is advisory.
    doc = _metric_doc().replace(
        "**Included**: x\n\n**Excluded**: y", "Only paying customers."
    )
    errors, warnings = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert not any("Scope" in e for e in errors)
    assert any("Scope" in w and "Included" in w for w in warnings)


def test_dos_and_donts_missing_a_dont_warns_not_blocks():
    doc = _metric_doc().replace(
        "**Do:**\n\n- do this\n\n**Don't:**\n\n- not that", "- Always use is_current"
    )
    errors, warnings = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert not any("Dos and Don'ts" in e for e in errors)
    assert any("Do and one Don't" in w for w in warnings)


@pytest.mark.parametrize(
    "omit,needle",
    [
        ("## Ownership", "Missing ## Ownership section"),
        ("## Overview", "Missing ## Overview section"),
        (
            "## Related Business Entities",
            "Missing ## Related Business Entities section",
        ),
        ("## Glossary and Synonyms", "Missing ## Glossary and Synonyms section"),
        ("## Scope", "Missing ## Scope section"),
        ("## Calculation", "Missing ## Calculation section"),
        ("## Dos and Don'ts", "Missing ## Dos and Don'ts section"),
        ("## Golden Queries", "Golden Queries"),
        ("## Catalog", "Catalog"),
    ],
)
def test_metric_requires_each_documented_section(omit, needle):
    # Every section the template/skill mark required is enforced for metrics — the
    # ENFORCED set is kept equal to the DOCUMENTED set so the two can't drift.
    parsed = parse_entity_markdown(_metric_doc(omit=omit))
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any(needle in e for e in errors), (omit, errors)


_DOMAIN_PARTS = [
    (
        "## Ownership",
        "**Data Owner:**\n- owner@quintoandar.com.br\n\n"
        "**Data Steward:**\n- steward@quintoandar.com.br",
    ),
    ("## Overview", "Business context for the domain."),
    ("## Glossary and Synonyms", "- **termo** → maps to something"),
    ("## Tables", "The canonical table is `schema.my_table`."),
    ("## Key Metrics", "- **Volume:** `COUNT(*)` on `schema.my_table`."),
    (
        "## Relationships with other entities",
        "- **My Domain ↔ Contact:** join on `sk_contact`.",
    ),
    ("## Dos and Don'ts", "**Do:**\n\n- use canonical\n\n**Don't:**\n\n- raw"),
    ("## Golden Queries", "```sql\nSELECT count(*) FROM schema.my_table\n```"),
]


def _domain_doc(omit: str | None = None) -> str:
    out = "# My Domain\n\n"
    for heading, content in _DOMAIN_PARTS:
        if heading == omit:
            continue
        out += f"{heading}\n\n{content}\n\n"
    return out


@pytest.mark.parametrize(
    "omit,needle",
    [
        ("## Key Metrics", "Key Metrics"),
        ("## Relationships with other entities", "Relationships"),
    ],
)
def test_domain_requires_key_metrics_and_relationships(omit, needle):
    parsed = parse_entity_markdown(_domain_doc(omit=omit))
    errors, _ = validate_parsed_document(parsed, data_product_type="domain")
    assert any(needle in e for e in errors), (omit, errors)


def test_domain_key_metrics_html_comment_only_is_empty():
    doc = _domain_doc().replace(
        "## Key Metrics\n\n- **Volume:** `COUNT(*)` on `schema.my_table`.\n\n",
        "## Key Metrics\n\n<!-- template hint -->\n\n",
    )
    parsed = parse_entity_markdown(doc)
    errors, _ = validate_parsed_document(parsed, data_product_type="domain")
    assert any("Key Metrics" in e for e in errors)


def test_h3_under_unrelated_h2_is_not_a_golden_query():
    # Regression: an H3 named "Golden Query — ..." nested under an arbitrary
    # segment H2 (no ## Golden Queries heading anywhere) must NOT be picked up.
    # generate_and_push_datahub_entities.py only opens a golden-query zone on an
    # H2 (`## Golden query: {Name}` / `## Golden Queries`) and never on an H3
    # under an unrelated parent — so if this parser accepted it, a doc could pass
    # validation here while the publisher extracts zero golden queries from the
    # same file (and the raw SQL/table names would leak into the Data Product
    # description instead, since `## For Rent (RENT)` matches none of
    # EXCLUDE_HEADING_PATTERNS).
    doc = """\
# Listing Demand Funnel

## Overview

Listing cohort conversions.

## For Rent (RENT)

### Golden Query — RENT listing cohort + demand flags (pattern)

```sql
SELECT sk_house_listing, flg_visit_completed
FROM dw_rent.fact_listing_rent_flows
```

## Superset Golden Assets

- `dw_rent.fact_listing_rent_flows`
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.golden_queries == []
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any("Golden Queries" in e for e in errors), errors


def test_standalone_h2_golden_query_heading_matches_publisher_shape():
    # The legitimately-supported inline pattern: a standalone H2
    # `## Golden query: {Name}` heading instead of a `## Golden Queries` section —
    # exactly the shape `_GOLDEN_QUERY_SINGULAR_HEADING_RE` requires in the
    # publisher, so both sides agree on what counts as a golden query here.
    doc = """\
# Listing Demand Funnel

## Overview

Listing cohort conversions.

## Golden query: RENT listing cohort + demand flags

```sql
SELECT sk_house_listing, flg_visit_completed
FROM dw_rent.fact_listing_rent_flows
```
"""
    parsed = parse_entity_markdown(doc)
    assert len(parsed.golden_queries) == 1
    assert "fact_listing_rent_flows" in parsed.golden_queries[0].sql


def test_golden_queries_section_preferred_over_inline_headings():
    doc = """\
# Payments

## Golden Queries

### Query 1 — Payment volume

```sql
SELECT 1 AS x FROM dw_a.fact_b
```

## For Rent (RENT)

### Golden Query — RENT inline (must not be picked up)

```sql
SELECT 2 AS y FROM dw_a.fact_b
```
"""
    parsed = parse_entity_markdown(doc)
    assert len(parsed.golden_queries) == 1
    assert "Payment volume" in parsed.golden_queries[0].name
    assert "x" in parsed.golden_queries[0].sql
    assert "y" not in parsed.golden_queries[0].sql
