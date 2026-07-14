"""Generate data_product_curated_entity YAML from parsed TARS entity documents."""

from __future__ import annotations

import re
import textwrap
import uuid
from typing import Any, Optional

import yaml

from sync.constants import (
    DATA_PRODUCT_TYPE_METRIC,
    GITHUB_REPO,
    LIFECYCLE_STAGE_PROD,
    MD_OUTPUT_DIR,
    MD_OUTPUT_DIR_METRICS,
    STRUCTURED_PROP_GOLDEN_QUERY,
)
from sync.document_parser import (
    ParsedEntityDocument,
    extract_subjects_from_sql,
)

# Stable URN namespace — same as generate_and_push_datahub_entities.py so the TARS
# sync and CI flows produce the same deterministic URN for index-0 when a data_product_id
# is known (position 1+ URNs are always derived from data_product_id + index).
_URN_NAMESPACE = uuid.UUID("5f4dcc3b-5aa7-4b63-e02b-eea7b56af02c")


def _kebab_case(slug: str) -> str:
    return slug.strip().lower().replace("_", "-")


def _entity_slug(data_product_id: str) -> str:
    return data_product_id.replace("-", "_")


def _condense_overview(
    overview: str,
    entity_slug: str,
    max_paragraphs: int = 6,
    *,
    md_output_dir: str = MD_OUTPUT_DIR,
) -> str:
    paragraphs = [p.strip() for p in overview.split("\n\n") if p.strip()]
    selected = paragraphs[:max_paragraphs]
    body = "\n\n".join(selected)
    suffix = f"\n\nFurther detail and table routing: {md_output_dir}/{entity_slug}.md"
    if suffix.strip() not in body:
        body += suffix
    return body


def _glossary_parent_node(domain_urn: str, override: Optional[str]) -> str:
    if override:
        return override
    if domain_urn.startswith("urn:li:domain:"):
        return domain_urn.replace("urn:li:domain:", "urn:li:glossaryNode:", 1)
    return "urn:li:glossaryNode:fintech"


def _gq_stable_urn(product_id: str, index: int, base_urn: Optional[str] = None) -> str:
    """Deterministic per-query URN.

    Index 0 uses ``base_urn`` when provided (stored stable URN from the TARS document),
    falling back to uuid5(product_id) so it remains stable even when the stored URN is
    absent. Index 1+ always derive from product_id + index via uuid5.
    """
    if index == 0 and base_urn:
        return base_urn
    key = product_id if index == 0 else f"{product_id}:{index}"
    return f"urn:li:query:{uuid.uuid5(_URN_NAMESPACE, key)}"


def _resolve_datasets(
    parsed: ParsedEntityDocument,
    *,
    data_product_type: str,
    primary_datasets: Optional[list[tuple[str, str]]],
    all_gq_subjects: list[tuple[str, str]],
) -> list[dict[str, str]]:
    """Build the ``datasets`` list for the YAML spec (Trino rows and/or Superset URNs)."""
    if data_product_type == DATA_PRODUCT_TYPE_METRIC and parsed.metric_dataset_rows:
        return list(parsed.metric_dataset_rows)
    if primary_datasets:
        return [{"schema": s, "table": t} for s, t in primary_datasets]
    if parsed.datasets:
        return [{"schema": s, "table": t} for s, t in parsed.datasets]
    return [{"schema": s, "table": t} for s, t in all_gq_subjects]


def _gq_subject_rows(
    datasets: list[dict[str, str]],
) -> list[tuple[str, str]]:
    """Return schema/table pairs from dataset rows for golden-query subjects."""
    subjects: list[tuple[str, str]] = []
    for row in datasets:
        schema = row.get("schema")
        table = row.get("table")
        if schema and table:
            subjects.append((schema, table))
    return subjects


def build_datahub_yaml(
    parsed: ParsedEntityDocument,
    *,
    data_product_id: str,
    domain_urn: str,
    lifecycle_stage: Optional[str] = None,
    golden_query_stable_urn: Optional[str] = None,
    glossary_parent_node_urn: Optional[str] = None,
    primary_datasets: Optional[list[tuple[str, str]]] = None,
    source_document_urn: Optional[str] = None,
    data_product_type: str = "domain",
) -> dict[str, Any]:
    """Build a ``kind: data_product_curated_entity`` spec dict."""
    product_id = _kebab_case(data_product_id)
    entity_slug = _entity_slug(product_id)
    # Metric docs have no ## Tables section (they link to the business entity), so
    # parsed.datasets is often empty — fall back to the golden queries' FROM/JOIN
    # tables so the loader still gets a non-empty datasets list.
    all_gq_subjects: list[tuple[str, str]] = []
    for gq in parsed.golden_queries:
        for pair in extract_subjects_from_sql(gq.sql):
            if pair not in all_gq_subjects:
                all_gq_subjects.append(pair)
    dataset_rows = _resolve_datasets(
        parsed,
        data_product_type=data_product_type,
        primary_datasets=primary_datasets,
        all_gq_subjects=all_gq_subjects,
    )
    gq_subject_fallback = _gq_subject_rows(dataset_rows) or all_gq_subjects
    md_output_dir = (
        MD_OUTPUT_DIR_METRICS
        if data_product_type == DATA_PRODUCT_TYPE_METRIC
        else MD_OUTPUT_DIR
    )

    spec: dict[str, Any] = {
        "spec_version": 1,
        "kind": "data_product_curated_entity",
        "product_display_name": parsed.title,
        "product_description": _condense_overview(
            parsed.overview, entity_slug, md_output_dir=md_output_dir
        ),
        "data_product_id": product_id,
        "domain_urn": domain_urn,
        "lifecycle_stage": lifecycle_stage or LIFECYCLE_STAGE_PROD,
        "data_product_type": data_product_type,
        "structured_property": {
            "qualified_name": STRUCTURED_PROP_GOLDEN_QUERY,
            "legacy_qualified_names_to_drop": [
                f"br.com.quintoandar.datahub.{product_id}.golden_query",
                f"br.com.quintoandar.datahub.{product_id}.golden_query_url",
            ],
        },
        "datasets": dataset_rows,
        "documentation_link": {
            "label": f"Business entity documentation ({entity_slug}.md)",
            "url": (
                f"https://github.com/{GITHUB_REPO}/blob/master/"
                f"{md_output_dir}/{entity_slug}.md"
            ),
        },
    }

    # Golden queries are optional (metric data products may have none). The loader
    # skips the golden-query step when the key is absent. Emit plural golden_queries:
    # list so ALL queries are pushed; the legacy singular golden_query: key is only used
    # when there is exactly one query and backward-compat is needed.
    if parsed.golden_queries:
        gq_list = []
        for i, gq in enumerate(parsed.golden_queries):
            gq_subjects = extract_subjects_from_sql(gq.sql) or gq_subject_fallback[:3]
            gq_list.append(
                {
                    "stable_urn": _gq_stable_urn(
                        product_id, i, golden_query_stable_urn
                    ),
                    "name": gq.name,
                    "description": textwrap.dedent(
                        f"""\
                    {gq.description}
                    Source: {md_output_dir}/{entity_slug}.md"""
                    ).strip(),
                    "subjects": [{"schema": s, "table": t} for s, t in gq_subjects],
                    "sql": gq.sql,
                }
            )
        spec["golden_queries"] = gq_list

    if parsed.glossary_terms:
        spec["glossary_terms"] = {
            "parent_node_urn": _glossary_parent_node(
                domain_urn, glossary_parent_node_urn
            ),
            "terms": [
                {
                    "id": term.term_id,
                    "name": term.name,
                    "description": term.description,
                }
                for term in parsed.glossary_terms
            ],
        }

    # Ownership (## Ownership) — applies to both domain and metric products. Only emit
    # roles that actually have resolved @quintoandar.com / @quintoandar.com.br emails.
    owners_block = {
        role: emails for role, emails in (parsed.owners or {}).items() if emails
    }
    if owners_block:
        spec["owners"] = owners_block

    # MBR (## MBR) — metric products only; the loader clears membership when absent.
    if data_product_type == DATA_PRODUCT_TYPE_METRIC and parsed.mbr:
        spec["mbr"] = list(parsed.mbr)

    if data_product_type == DATA_PRODUCT_TYPE_METRIC and parsed.related_data_products:
        spec["related_data_products"] = list(parsed.related_data_products)

    if source_document_urn:
        spec["source_context_document_urn"] = source_document_urn

    return spec


def render_yaml(spec: dict[str, Any]) -> str:
    return yaml.dump(
        spec,
        default_flow_style=False,
        allow_unicode=True,
        sort_keys=False,
        width=100,
    )


def build_markdown_file(
    parsed: ParsedEntityDocument, data_product_urn: Optional[str] = None
) -> str:
    """Return cleaned markdown for Git (strip authoring checklist blockquote)."""
    lines = parsed.raw_markdown.splitlines()
    out: list[str] = []
    skip_blockquote = False
    for line in lines:
        if line.startswith("> **Authoring checklist"):
            skip_blockquote = True
            continue
        if skip_blockquote:
            if line.startswith(">") or line.strip() == "":
                continue
            skip_blockquote = False
        out.append(line)

    md = "\n".join(out).strip()
    if data_product_urn and "## DataHub catalog" in md:
        catalog = (
            f"\n\n## DataHub catalog\n\n- **Data Product:** `{data_product_urn}`\n"
        )
        md = re.sub(
            r"(?s)## DataHub catalog.*?(?=\n## |\Z)",
            catalog.strip(),
            md,
            count=1,
        )
    elif data_product_urn:
        md += f"\n\n## DataHub catalog\n\n- **Data Product:** `{data_product_urn}`\n"
    return md + "\n"
