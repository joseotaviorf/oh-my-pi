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

# One ``### {Metric Name}`` block with every per-metric field the template documents.
_METRIC_ENTRY = (
    "### My Metric\n\n"
    "#### Slug\n\n"
    "my_metric\n\n"
    "#### Description\n\n"
    "What it measures and why the naive path is wrong.\n\n"
    "#### Also Known As\n\n"
    "- **taxa de re-locação**, **re-rental rate**\n"
    "- **RR** → near-miss — Recovery Rate, a Fintech metric, not this one\n\n"
    "#### Rules\n\n"
    "Canonical filter: status = 'active'. Weights come from the parameter table.\n\n"
    "#### Type\n\n"
    "OKR\n\n"
    "#### Direction\n\n"
    "Higher is better\n\n"
    "#### Grain\n\n"
    "monthly\n\n"
    "#### Is Additive\n\n"
    "false\n\n"
    "#### Business Stage\n\n"
    "Post Contract\n\n"
    "#### Acronym\n\n"
    "MM\n\n"
    "#### MBR\n\n"
    "Post Contract\n\n"
    "#### Category\n\n"
    "Quality\n\n"
    "#### Golden Query\n\n"
    "Monthly value.\n\n"
    "```sql\nSELECT count(*) FROM dw.my_table\n```"
)

# A metric doc carrying every section the template/skill document as required.
# Tests that check a specific missing section omit exactly one part from this set.
_METRIC_PARTS = [
    (
        "## Ownership",
        "**Data Owner:**\n- owner@quintoandar.com.br\n\n"
        "**Data Steward:**\n- steward@quintoandar.com.br",
    ),
    ("## Description", "What this family of metrics measures and why it is tracked."),
    ("## Domain", "For Rent"),
    ("## Glossary and Synonyms", "- **My Metric** → My Metric"),
    ("## Related Domain Entities", "- Contact"),
    ("## Metrics", _METRIC_ENTRY),
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


def test_related_domain_entities_parsed_to_product_ids():
    doc = """\
# Metric

## Overview

Body.

## Related Domain Entities

- NPS
- House and Listing
"""
    parsed = parse_entity_markdown(doc)
    assert parsed.related_data_products == ["nps", "house-and-listing"]
    assert parsed.has_related_domain_entities_section is True


def test_related_domain_entities_html_comment_is_not_an_entity():
    # Regression: ``<!-- optional -->`` slugifies to ``optional`` if comments are
    # not stripped, so CI would accept a template leftover as a related product.
    # ``## Related Domain Entities`` is now optional, so a comment-only body is a
    # present-but-empty optional section (blocking), not a missing required one.
    parsed = parse_entity_markdown(
        _metric_doc().replace("- Contact", "<!-- optional -->")
    )
    assert parsed.has_related_domain_entities_section is True
    assert parsed.related_data_products == []
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any(
        "related domain entities" in e.lower() and "empty" in e.lower() for e in errors
    )


def test_related_domain_entities_keeps_bullets_beside_html_comments():
    parsed = parse_entity_markdown(
        _metric_doc().replace(
            "- Contact", "- House and Listing\n<!-- template hint -->"
        )
    )
    assert parsed.related_data_products == ["house-and-listing"]
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert not any("Related Domain Entities" in e for e in errors)


def test_braces_in_prose_fields_are_not_read_as_unfilled_placeholders():
    """Bugbot regression: ``_is_placeholder`` is a contains-a-brace test written for
    scalar values like ``{MBR Name}``. Applied to the multi-line ``#### Description``
    / ``#### Rules`` bodies it rejected filled prose — a parameter placeholder, JSON,
    or set notation — with a misleading "missing heading" error. A genuinely unfilled
    section is still caught by the file-level placeholder scan in
    ``validate_datahub_context_entities``, which strips code fences first."""
    parsed = parse_entity_markdown(
        _metric_doc()
        .replace(
            "Canonical filter: status = 'active'. Weights come from the parameter "
            "table.",
            "Canonical filter: `dt BETWEEN {load_start_date} AND {load_end_date}`. "
            "Statuses in {active, pending} count; the payload is "
            '`{"kind": "rent"}`.',
        )
        .replace(
            "What it measures and why the naive path is wrong.",
            "Share of contracts closed in {period}, unlike the naive count.",
        ),
        fallback_title="My Metric",
    )
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert not [e for e in errors if "#### Rules" in e or "#### Description" in e]


def test_scalar_field_left_as_template_token_is_still_rejected():
    """The brace test must stay in force for scalar values, which are exactly where
    an unfilled token looks identical to a real answer."""
    parsed = parse_entity_markdown(
        _metric_doc().replace("#### Grain\n\nmonthly", "#### Grain\n\n{grain}"),
        fallback_title="My Metric",
    )
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any("#### Grain" in e for e in errors)


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


def test_metric_related_domain_entities_is_optional_when_absent():
    # ``## Related Domain Entities`` is now inferred + optional: a complete doc that
    # omits it entirely must still pass (no "missing section" error).
    parsed = parse_entity_markdown(_metric_doc(omit="## Related Domain Entities"))
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert errors == []
    assert warnings == []


def test_metric_related_domain_entities_present_but_empty_is_blocking():
    # Present-but-empty optional section is still invalid — omit it instead.
    doc = (
        _metric_doc(omit="## Related Domain Entities")
        + "## Related Domain Entities\n\n\n"
    )
    parsed = parse_entity_markdown(doc)
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert any(
        "related domain entities" in err.lower() and "empty" in err.lower()
        for err in errors
    )
    assert not any("Related Domain Entities" in warn for warn in warnings)


def test_metric_missing_description_is_blocking():
    parsed = parse_entity_markdown(_metric_doc(omit="## Description"))
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any("Missing ## Description section" in e for e in errors)


def test_metric_doc_matching_neither_format_is_blocking():
    # No ## Metrics heading routes the doc to the legacy contract, which then reports
    # the legacy sections it is missing — it must not pass by falling between the two.
    parsed = parse_entity_markdown(_metric_doc(omit="## Metrics"))
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any("## Calculation" in e for e in errors)


# A metric doc in the pre-redesign shape. Both formats are accepted for the whole
# migration window, so this fixture guards the property that matters most during it:
# touching a not-yet-migrated document must not fail CI.
_LEGACY_METRIC_DOC = """\
# My Metric

## Ownership

**Data Owner:**
- owner@quintoandar.com.br

**Data Steward:**
- steward@quintoandar.com.br

## Overview

What this metric measures and why it is tracked.

## Glossary and Synonyms

- **My Metric** → My Metric

## Catalog

| Metric | Type |
|---|---|
| My Metric | OKR |

## Related Domain Entities

- Contact

## Scope

Included: active contracts. Excluded: cancelled contracts.

## Calculation

### Canonical Filter

`status = 'active'`

### Nuances

Do not sum across segments.

## Dos and Don'ts

- Do filter by status.
- Don't sum the ratio across segments.

## Golden Queries

### Query 1 — Monthly value

Monthly value of My Metric.

```sql
SELECT count(*) FROM dw.my_table
```
"""


def test_legacy_metric_doc_still_validates():
    parsed = parse_entity_markdown(_LEGACY_METRIC_DOC)
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert errors == []


def test_legacy_metric_doc_missing_calculation_still_blocks():
    # Accepting the legacy format must not mean accepting an incomplete legacy doc.
    doc = _LEGACY_METRIC_DOC.replace("## Calculation", "## Something Else")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("## Calculation" in e for e in errors)


def test_description_falls_back_into_overview():
    # tars-evals builds the Data Product description and search text from
    # ``parsed.overview``; a redesigned doc names that section ## Description.
    parsed = parse_entity_markdown(_metric_doc())
    assert "family of metrics" in parsed.overview


def test_related_domain_entities_does_not_satisfy_domain():
    # ## Related Domain Entities contains the word "domain"; a substring match would
    # read its bullets as the entity's metadata domain and pass silently.
    doc = _metric_doc(omit="## Domain")
    parsed = parse_entity_markdown(doc)
    assert parsed.domain == ""


@pytest.mark.parametrize(
    "heading,bad_value",
    [
        ("#### Type", "Guardrail"),
        ("#### Direction", "Up"),
        ("#### Grain", "hourly"),
        ("#### Is Additive", "sometimes"),
        ("#### Business Stage", "Suply"),
    ],
)
def test_per_metric_enum_outside_vocabulary_is_blocking(heading, bad_value):
    original = {
        "#### Type": "OKR",
        "#### Direction": "Higher is better",
        "#### Grain": "monthly",
        "#### Is Additive": "false",
        "#### Business Stage": "Post Contract",
    }[heading]
    doc = _metric_doc().replace(
        f"{heading}\n\n{original}\n", f"{heading}\n\n{bad_value}\n"
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("allowed values are" in e for e in errors), errors


def test_per_metric_enum_accepts_any_casing():
    doc = _metric_doc().replace(
        "#### Direction\n\nHigher is better\n", "#### Direction\n\nHIGHER IS BETTER\n"
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert errors == []


def test_non_snake_case_slug_is_blocking():
    doc = _metric_doc().replace("#### Slug\n\nmy_metric\n", "#### Slug\n\nMy Metric\n")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("snake_case" in e for e in errors)


def test_duplicate_metric_slug_is_blocking():
    # The slug names the table the generator phase will materialize; two metrics
    # claiming the same one would collapse into a single output.
    doc = _metric_doc() + _METRIC_ENTRY.replace("### My Metric", "### Other Metric")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Duplicate metric slug" in e for e in errors)


def test_duplicate_metric_name_is_blocking():
    doc = _metric_doc() + _METRIC_ENTRY.replace(
        "#### Slug\n\nmy_metric", "#### Slug\n\nanother_metric"
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Duplicate metric name" in e for e in errors)


def test_duplicate_h4_heading_warns():
    # The later block silently wins; a corrected value going unread is worth saying.
    doc = _metric_doc().replace(
        "#### Acronym\n\nMM\n", "#### Acronym\n\nMM\n\n#### Acronym\n\nMMX\n"
    )
    errors, warnings = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert errors == []
    assert any("more than once" in w for w in warnings)


def test_per_metric_golden_queries_win_over_a_stray_legacy_heading():
    # A leftover ``## Golden query: …`` H2 must not shadow the per-metric queries the
    # CI gate is supposed to check — it would validate the leftover and skip the rest.
    doc = (
        _metric_doc()
        + "## Golden query: leftover\n\n```sql\nSELECT 1 FROM dw.stale\n```\n"
    )
    parsed = parse_entity_markdown(doc)
    assert [gq.sql for gq in parsed.golden_queries] == [
        "SELECT count(*) FROM dw.my_table"
    ]


def test_metric_missing_per_metric_direction_is_blocking():
    doc = _metric_doc().replace("#### Direction\n\nHigher is better\n\n", "")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Direction" in e for e in errors)


def test_metric_missing_per_metric_golden_query_is_blocking():
    doc = _metric_doc().replace(
        "#### Golden Query\n\nMonthly value.\n\n"
        "```sql\nSELECT count(*) FROM dw.my_table\n```",
        "",
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Golden Query" in e for e in errors)


def test_metric_missing_per_metric_description_is_blocking():
    doc = _metric_doc().replace(
        "#### Description\n\nWhat it measures and why the naive path is wrong.\n\n",
        "",
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("#### Description" in e for e in errors)


def test_metric_present_but_empty_optional_mbr_heading_is_blocking():
    doc = _metric_doc().replace(
        "#### MBR\n\nPost Contract\n\n#### Category\n\nQuality\n\n",
        "#### MBR\n\n#### Category\n\nQuality\n\n",
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("mbr" in e.lower() and "empty" in e.lower() for e in errors)


def test_metric_without_acronym_is_valid():
    # Acronym is optional: requiring it is what filled the existing metric layer with
    # the metric name repeated and coined initialisms nobody uses.
    doc = _metric_doc().replace("#### Acronym\n\nMM\n\n", "")
    errors, warnings = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert errors == []
    assert not any("acronym" in w.lower() for w in warnings)


def test_redesigned_metric_doc_needs_no_entity_level_glossary():
    # Aliases moved into each metric. Demanding the entity-level section as well would
    # reject every document the current questionnaire produces.
    doc = _metric_doc(omit="## Glossary and Synonyms")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert not any("Glossary" in e for e in errors), errors


def test_metric_missing_its_own_aliases_is_blocking():
    doc = _metric_doc().replace(
        "#### Also Known As\n\n"
        "- **taxa de re-locação**, **re-rental rate**\n"
        "- **RR** → near-miss — Recovery Rate, a Fintech metric, not this one\n\n",
        "",
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Also Known As" in e for e in errors), errors


def test_legacy_metric_doc_still_requires_the_entity_glossary():
    # No ``## Metrics`` section means the pre-redesign contract, where the entity-level
    # list is the only place aliases exist.
    doc = _LEGACY_METRIC_DOC.replace(
        "## Glossary and Synonyms\n\n- **My Metric** → My Metric\n\n", ""
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Missing ## Glossary and Synonyms section" in e for e in errors), errors


def test_per_metric_aliases_flatten_into_the_document_glossary():
    # The published payload must not depend on which template authored the document.
    parsed = parse_entity_markdown(_metric_doc())
    by_name = {term.name: term.description for term in parsed.glossary_terms}
    assert by_name["taxa de re-locação (re-rental rate)"] == "My Metric"
    assert by_name["RR"] == "near-miss — Recovery Rate, a Fintech metric, not this one"


def test_metric_without_business_stage_is_valid():
    # The questionnaire no longer asks for it: for 6 of the 7 domains the stage is the
    # domain restated, and nothing downstream reads the column. Documents authored
    # without it must publish cleanly.
    doc = _metric_doc().replace("#### Business Stage\n\nPost Contract\n\n", "")
    errors, warnings = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert errors == []
    assert not any("business stage" in w.lower() for w in warnings)


def test_metric_with_business_stage_still_publishes_it():
    # The other half of "optional": the ~700 metrics that already carry a stage keep
    # validating, and the value still reaches the payload.
    parsed = parse_entity_markdown(_metric_doc(), fallback_title="My Metric")
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert errors == []
    assert parsed.metrics[0].business_stage == "Post Contract"


def test_metric_present_but_empty_business_stage_heading_is_blocking():
    doc = _metric_doc().replace(
        "#### Business Stage\n\nPost Contract\n\n", "#### Business Stage\n\n"
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("business stage" in e.lower() and "empty" in e.lower() for e in errors)


def test_metric_present_but_empty_acronym_heading_is_blocking():
    doc = _metric_doc().replace("#### Acronym\n\nMM\n\n", "#### Acronym\n\n")
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("acronym" in e.lower() and "empty" in e.lower() for e in errors)


def test_metric_category_without_mbr_warns_not_blocks():
    doc = _metric_doc().replace("#### MBR\n\nPost Contract\n\n", "")
    errors, warnings = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert not any("Category" in e for e in errors)
    assert any("Category" in w and "MBR" in w for w in warnings)


def test_metric_more_than_ten_metrics_is_blocking():
    entries = "\n\n".join(
        f"### Metric {i}\n\n"
        "#### Description\n\nWhat it measures.\n\n"
        "#### Direction\n\nHigher is better\n\n"
        "#### Golden Query\n\nValue.\n\n```sql\nSELECT 1 FROM dw.t\n```"
        for i in range(11)
    )
    doc = _metric_doc().replace(_METRIC_ENTRY, entries)
    parsed = parse_entity_markdown(doc)
    assert len(parsed.metrics) == 11
    errors, _ = validate_parsed_document(parsed, data_product_type="metric")
    assert any("maximum is 10" in e for e in errors)


def test_metric_per_metric_golden_queries_feed_parsed_golden_queries():
    # The golden-query metadata/Spark-construct CI gate reads parsed.golden_queries;
    # the new template has no top-level ## Golden Queries, so per-metric queries must
    # populate it.
    entries = (
        "### Metric A\n\n"
        "#### Description\n\nA.\n\n#### Direction\n\nHigher is better\n\n"
        "#### Golden Query\n\nA value.\n\n```sql\nSELECT 1 AS a FROM dw.t\n```\n\n"
        "### Metric B\n\n"
        "#### Description\n\nB.\n\n#### Direction\n\nLower is better\n\n"
        "#### Golden Query\n\nB value.\n\n```sql\nSELECT 2 AS b FROM dw.t\n```"
    )
    doc = _metric_doc().replace(_METRIC_ENTRY, entries)
    parsed = parse_entity_markdown(doc)
    assert len(parsed.golden_queries) == 2
    sqls = " ".join(q.sql for q in parsed.golden_queries)
    assert "a" in sqls and "b" in sqls


def test_complete_metric_doc_passes():
    parsed = parse_entity_markdown(_metric_doc())
    errors, warnings = validate_parsed_document(parsed, data_product_type="metric")
    assert errors == []
    assert warnings == []


@pytest.mark.parametrize(
    "omit,needle",
    [
        ("## Ownership", "Missing ## Ownership section"),
        ("## Description", "Missing ## Description section"),
        ("## Domain", "Missing ## Domain section"),
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


def test_complete_domain_doc_passes():
    parsed = parse_entity_markdown(_domain_doc())
    errors, warnings = validate_parsed_document(parsed, data_product_type="domain")
    assert errors == []
    assert warnings == []


def test_domain_ownership_steward_only_is_sufficient():
    # Domain docs no longer require a Data Owner — a Data Steward alone is enough.
    doc = _domain_doc().replace(
        "**Data Owner:**\n- owner@quintoandar.com.br\n\n"
        "**Data Steward:**\n- steward@quintoandar.com.br",
        "**Data Steward:**\n- steward@quintoandar.com.br",
    )
    parsed = parse_entity_markdown(doc)
    assert parsed.owners["data_owner"] == []
    errors, _ = validate_parsed_document(parsed, data_product_type="domain")
    assert not any("Ownership" in e for e in errors)
    assert not any("Data Owner" in e for e in errors)


def test_domain_ownership_missing_steward_is_blocking():
    # A Data Steward is still required for domain docs even though Data Owner is not.
    doc = _domain_doc().replace(
        "**Data Owner:**\n- owner@quintoandar.com.br\n\n"
        "**Data Steward:**\n- steward@quintoandar.com.br",
        "**Data Owner:**\n- owner@quintoandar.com.br",
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="domain"
    )
    assert any("Data Steward" in e for e in errors)
    assert not any("Data Owner" in e for e in errors)


def test_metric_ownership_requires_both_owner_and_steward():
    # Metric docs still require BOTH a Data Owner and a Data Steward.
    doc = _metric_doc().replace(
        "**Data Owner:**\n- owner@quintoandar.com.br\n\n"
        "**Data Steward:**\n- steward@quintoandar.com.br",
        "**Data Steward:**\n- steward@quintoandar.com.br",
    )
    errors, _ = validate_parsed_document(
        parse_entity_markdown(doc), data_product_type="metric"
    )
    assert any("Data Owner" in e for e in errors)


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
    # Validated as a domain doc: domain still requires a ## Golden Queries SQL block,
    # so the H3-under-unrelated-H2 (not picked up) surfaces as the missing-golden error.
    errors, _ = validate_parsed_document(parsed, data_product_type="domain")
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
