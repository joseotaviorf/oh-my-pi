"""Local, offline sources for the DataHub-shaped backend. Everything is read
from the parent bi-etl-ejuice repo (single source of truth): data products +
golden queries from docs/llm_context via the repo's own document_parser, and
column schema from bietlejuice metadata/**.yml. Cached at first use."""

from __future__ import annotations

import functools

import yaml

from tars_evals.datahub_mock.entities import DataProduct, build_data_product
from tars_evals.repo_bootstrap import load_document_parser, repo_root

# Stable aliases so callers (and tests) share the bootstrap cache/module identity.
_document_parser = load_document_parser


@functools.cache
def load_data_products() -> dict[str, DataProduct]:
    """Load every business AND metric entity as a DataProduct — both are
    published to DataHub and discoverable by tars. Metric entities are thinner
    (often no ## Tables / golden query; see document_parser.validate_parsed_document),
    which the entity model tolerates."""
    parser = _document_parser()
    out: dict[str, DataProduct] = {}
    for subdir in ("domain_entities", "metric_entities"):
        md_dir = repo_root() / "docs/llm_context" / subdir
        for md in sorted(md_dir.glob("*.md")):
            if md.name == "_TEMPLATE.md":
                continue
            slug = md.stem.replace("_", "-")
            parsed = parser.parse_entity_markdown(
                md.read_text(), fallback_title=md.stem
            )
            out[slug] = build_data_product(slug, parsed)
    return out


@functools.cache
def column_index() -> dict[tuple[str, str], list[dict]]:
    idx: dict[tuple[str, str], list[dict]] = {}
    for yml in (repo_root() / "dags").rglob("metadata/**/*.yml"):
        try:
            doc = yaml.safe_load(yml.read_text())
        except (yaml.YAMLError, OSError):
            continue
        if not isinstance(doc, dict):
            continue
        db, table = doc.get("database_name"), doc.get("table_name")
        cols = doc.get("columns")
        if not (db and table and isinstance(cols, dict)):
            continue
        fields = []
        for name, meta in cols.items():
            # Metadata column values are normally a dict (description / lineage /
            # type / categories), but some yml use the string shorthand where the
            # value is just the description. Coerce to a dict so both parse.
            if isinstance(meta, dict):
                m = meta
            elif isinstance(meta, str):
                m = {"description": meta}
            else:
                m = {}
            fields.append(
                {
                    "fieldPath": name,
                    "nativeDataType": m.get("type", "unknown"),
                    "description": m.get("description"),
                }
            )
        idx[(db, table)] = fields
    return idx
