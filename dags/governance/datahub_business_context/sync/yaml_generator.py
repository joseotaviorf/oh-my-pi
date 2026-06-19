"""Generate data_product_curated_entity YAML from parsed TARS entity documents."""

from __future__ import annotations

import re
import textwrap
import uuid
from typing import Any, Optional

import yaml

from sync.constants import (
    GITHUB_REPO,
    LIFECYCLE_STAGE_PROD,
    MD_OUTPUT_DIR,
    STRUCTURED_PROP_GOLDEN_QUERY,
)
from sync.document_parser import (
    ParsedEntityDocument,
    extract_subjects_from_sql,
)


def _kebab_case(slug: str) -> str:
    return slug.strip().lower().replace("_", "-")


def _entity_slug(data_product_id: str) -> str:
    return data_product_id.replace("-", "_")


def _condense_overview(overview: str, entity_slug: str, max_paragraphs: int = 6) -> str:
    paragraphs = [p.strip() for p in overview.split("\n\n") if p.strip()]
    selected = paragraphs[:max_paragraphs]
    body = "\n\n".join(selected)
    suffix = f"\n\nFurther detail and table routing: {MD_OUTPUT_DIR}/{entity_slug}.md"
    if suffix.strip() not in body:
        body += suffix
    return body


def _glossary_parent_node(domain_urn: str, override: Optional[str]) -> str:
    if override:
        return override
    if domain_urn.startswith("urn:li:domain:"):
        return domain_urn.replace("urn:li:domain:", "urn:li:glossaryNode:", 1)
    return "urn:li:glossaryNode:fintech"


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
) -> dict[str, Any]:
    """Build a ``kind: data_product_curated_entity`` spec dict."""
    product_id = _kebab_case(data_product_id)
    entity_slug = _entity_slug(product_id)
    datasets = primary_datasets or parsed.datasets

    golden = parsed.golden_queries[0]
    stable_urn = golden_query_stable_urn or f"urn:li:query:{uuid.uuid4()}"
    subjects = extract_subjects_from_sql(golden.sql) or datasets[:3]

    spec: dict[str, Any] = {
        "spec_version": 1,
        "kind": "data_product_curated_entity",
        "product_display_name": parsed.title,
        "product_description": _condense_overview(parsed.overview, entity_slug),
        "data_product_id": product_id,
        "domain_urn": domain_urn,
        "lifecycle_stage": lifecycle_stage or LIFECYCLE_STAGE_PROD,
        "structured_property": {
            "qualified_name": STRUCTURED_PROP_GOLDEN_QUERY,
            "legacy_qualified_names_to_drop": [
                f"br.com.quintoandar.datahub.{product_id}.golden_query",
                f"br.com.quintoandar.datahub.{product_id}.golden_query_url",
            ],
        },
        "golden_query": {
            "stable_urn": stable_urn,
            "name": golden.name,
            "description": textwrap.dedent(
                f"""\
                {golden.description}
                Source: {MD_OUTPUT_DIR}/{entity_slug}.md"""
            ).strip(),
            "subjects": [{"schema": s, "table": t} for s, t in subjects],
            "sql": golden.sql,
        },
        "datasets": [{"schema": s, "table": t} for s, t in datasets],
        "documentation_link": {
            "label": f"Business entity documentation ({entity_slug}.md)",
            "url": (
                f"https://github.com/{GITHUB_REPO}/blob/master/"
                f"{MD_OUTPUT_DIR}/{entity_slug}.md"
            ),
        },
    }

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
