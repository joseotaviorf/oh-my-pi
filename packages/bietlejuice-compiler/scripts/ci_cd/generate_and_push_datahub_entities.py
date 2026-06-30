#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["requests", "pyyaml", "acryl-datahub"]
# ///
"""CI script: generates ephemeral .datahub.yaml per entity .md using LiteLLM
and publishes it to DataHub via load_collections_context.py.

Markdown is the only versioned source of truth. Generated YAML is written to a
temporary directory (never committed).

Entity kinds (see docs/llm_context/{business,metric}_entities/_TEMPLATE.md):
  domain — business_entities/*.md: table routing, Synonyms, owned datasets
  metric — metric_entities/*.md: calculation contract, upstream related_data_products,
           no owned datasets

Golden query ``stable_urn``: deterministic ``uuid5(entity_slug)`` — stable across
CI runs without a companion YAML in git.

Domain ``domain_urn``: fetched live from DataHub (``listDomains``) at CI start;
the LLM picks the best match from that catalog and the script validates before push.

Required env vars:
    OPENAI_API_KEY       — Bearer token for the internal LiteLLM proxy
    DATAHUB_GRAPHQL_URL  — Full URL to the DataHub GraphQL endpoint
    DATAHUB_TOKEN        — DataHub personal access token with editor role

Optional:
    LITELLM_MODEL        — override the default model "openai/gpt-5.3-codex"
    LITELLM_BASE_URL     — override the default proxy URL
    DATAHUB_CI_YAML_DIR  — override ephemeral YAML output directory

Usage in CI (auto-detects changed MDs via git diff):
    pip install requests acryl-datahub
    python packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py

Process every entity MD (loader resync / master full refresh):
    python .../generate_and_push_datahub_entities.py --all

Resync all entities when the loader changed in this commit, else changed MDs only:
    python .../generate_and_push_datahub_entities.py --resync-if-loader-changed

Usage locally — pass one or more MD file paths directly:
    uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py \\
        docs/llm_context/business_entities/my_entity.md

Exit codes:
    0 — all entities processed and published successfully (or no MDs to process)
    1 — one or more entities failed
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

import requests
import yaml

_REPO_ROOT = Path(__file__).resolve().parents[4]
_DATAHUB_CTX = _REPO_ROOT / "dags/governance/datahub_business_context"
if str(_DATAHUB_CTX) not in sys.path:
    sys.path.insert(0, str(_DATAHUB_CTX))

from datahub_domain_catalog import (  # noqa: E402
    DataHubDomain,
    entity_exists,
    fetch_all_domains,
    format_domains_for_prompt,
    known_domain_urns,
)

# Entity Markdown source directories. Both business and metric entities become Data
# Products in DataHub (the Woodpecker pipeline triggers on both paths).
_MD_DIRS = (
    _REPO_ROOT / "docs/llm_context/business_entities",
    _REPO_ROOT / "docs/llm_context/metric_entities",
)
_MD_PREFIXES = tuple(str(d.relative_to(_REPO_ROOT)) + "/" for d in _MD_DIRS)
_REFERENCE_DIR = _REPO_ROOT / "dags/governance/datahub_business_context/reference"
_LOADER = (
    _REPO_ROOT / "dags/governance/datahub_business_context/load_collections_context.py"
)
_LOADER_REL = "dags/governance/datahub_business_context/load_collections_context.py"
_SKILL_MD = _REPO_ROOT / ".cursor/skills/md-to-datahub-yaml/SKILL.md"
_GOLD_STANDARD = _REFERENCE_DIR / "payments.datahub.yaml"
_GLOSSARY_EXAMPLE = _REFERENCE_DIR / "visits.datahub.yaml"

# Fixed namespace — deterministic golden-query URN per entity slug.
_URN_NAMESPACE = uuid.UUID("a1b2c3d4-e5f6-7890-abcd-ef1234567890")

_QUERY_URN_RE = re.compile(
    r"^urn:li:query:" r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
# Allows an optional ``- `` list marker so it matches both the singular
# (``  stable_urn: …``) and the plural-list (``  - stable_urn: …``) YAML forms.
# The optional trailing ``(?:#[^\n]*)?`` absorbs YAML inline comments like
# ``  - stable_urn: "TBD"  # CI assigns the URN`` that the template emits.
_STABLE_URN_LINE_RE = re.compile(
    r"^(\s*(?:-\s+)?stable_urn:\s*)(?:urn:li:query:[^\s]+|\S+)\s*(?:#[^\n]*)?$",
    re.MULTILINE,
)

_DEFAULT_MODEL = "openai/gpt-5.3-codex"
_DEFAULT_BASE_URL = "https://litellm.apps.shared-prd.habitat.zone/v1"

# Markdown ``## `` sections that must NOT be folded into the Data Product description.
# Aligned with docs/llm_context/{business,metric}_entities/_TEMPLATE.md:
#   domain  — Where to query what → datasets; Synonyms → glossary; Golden query(ies) → Query entities
#   metric  — Related Business Entities → related_data_products SP; Glossary → glossary;
#             Golden Queries → Query entities; DataHub Catalog → tooling pointer only
EXCLUDE_HEADING_PATTERNS = [
    re.compile(r"^## (Tables|Where to query what)$", re.I),
    re.compile(r"^## (Synonyms|Glossary and Synonyms)$", re.I),
    re.compile(r"^## Golden [Qq]uer(y|ies)\b.*$", re.I),
    re.compile(r"^## DataHub [Cc]atalog$"),
    re.compile(r"^## Related Business Entities$", re.I),
    re.compile(r"^## Superset Golden Assets$", re.I),
]

# Matches the whole ``product_description:`` YAML block up to (but not including) the
# next top-level key (a line starting at column 0 with a non-space character).
_PRODUCT_DESCRIPTION_BLOCK_RE = re.compile(
    r"(?ms)^product_description:.*?\n(?=\S)",
)
# Used to insert a description block when the LLM omitted one entirely.
_PRODUCT_DISPLAY_NAME_LINE_RE = re.compile(
    r"(?m)^product_display_name:.*$",
)

_CI_YAML_DIR: Path | None = None

_DATA_PRODUCT_TYPE_RE = re.compile(r"(?m)^data_product_type:.*$")
_LIFECYCLE_STAGE_LINE_RE = re.compile(r"(?m)^lifecycle_stage:.*$")
_DOMAIN_URN_LINE_RE = re.compile(r"(?m)^domain_urn:.*$")
_DATASETS_BLOCK_RE = re.compile(r"(?ms)^datasets:.*?\n(?=\S|\Z)")
_RELATED_DATA_PRODUCTS_BLOCK_RE = re.compile(
    r"(?ms)^related_data_products:.*?\n(?=\S|\Z)"
)
_DOCUMENTATION_LINK_BLOCK_RE = re.compile(r"(?ms)^documentation_link:.*?\n(?=\S|\Z)")
_GITHUB_REPO = "quintoandar/bi-etl-ejuice"
_GITHUB_BRANCH = "master"
_SUPERSET_DATASET_URN_RE = re.compile(
    r"urn:li:dataset:\(urn:li:dataPlatform:superset,[^)]+\)",
    re.I,
)
_TRINO_TABLE_REF_RE = re.compile(r"`([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)`")


def md_path_to_data_product_id(md_path: Path) -> str:
    """``accounting_funnel.md`` → ``accounting-funnel``."""
    return md_path.stem.replace("_", "-")


def _md_to_data_product_type(md_path: Path) -> str:
    """Return 'metric' for metric_entities/, 'domain' for everything else."""
    return "metric" if "metric_entities" in md_path.parts else "domain"


def _llm_context_subdir(md_path: Path) -> str:
    return (
        "metric_entities" if "metric_entities" in md_path.parts else "business_entities"
    )


def _display_name_to_product_id(name: str) -> str:
    """``NPS`` → ``nps``; ``House and Listing`` → ``house-and-listing``."""
    return re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")


def _extract_section_body(md_text: str, *heading_substrings: str) -> str:
    """Return the body of the first ``##`` section whose title contains any substring."""
    lines = md_text.splitlines()
    body: list[str] = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            title = line[3:].strip().lower()
            in_section = any(sub.lower() in title for sub in heading_substrings)
            if in_section:
                body = []
            continue
        if in_section:
            body.append(line)
    return "\n".join(body).strip()


def _extract_related_data_products(md_path: Path) -> list[str]:
    """Parse ``## Related Business Entities`` bullets into kebab-case product IDs."""
    section = _extract_section_body(md_path.read_text(), "related business entities")
    ids: list[str] = []
    seen: set[str] = set()
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        product_id = _display_name_to_product_id(stripped[2:].strip())
        if product_id and product_id not in seen:
            seen.add(product_id)
            ids.append(product_id)
    return ids


def _documentation_link(md_path: Path, entity_slug: str) -> dict[str, str]:
    subdir = _llm_context_subdir(md_path)
    kind = "Metric entity" if subdir == "metric_entities" else "Business entity"
    return {
        "label": f"{kind} documentation ({entity_slug}.md)",
        "url": (
            f"https://github.com/{_GITHUB_REPO}/blob/{_GITHUB_BRANCH}/"
            f"docs/llm_context/{subdir}/{entity_slug}.md"
        ),
    }


def _as_yaml_list_block(key: str, values: list[str]) -> str:
    return f"{key}:\n" + "".join(f"  - {value}\n" for value in values)


def _inject_documentation_link(yaml_content: str, link: dict[str, str]) -> str:
    block = (
        "documentation_link:\n"
        f"  label: {json.dumps(link['label'])}\n"
        f"  url: >-\n"
        f"    {link['url']}\n"
    )
    if _DOCUMENTATION_LINK_BLOCK_RE.search(yaml_content):
        return _DOCUMENTATION_LINK_BLOCK_RE.sub(block, yaml_content, count=1)
    return yaml_content.rstrip() + f"\n{block}"


def _inject_related_data_products(yaml_content: str, product_ids: list[str]) -> str:
    if not product_ids:
        return yaml_content
    block = _as_yaml_list_block("related_data_products", product_ids)
    if _RELATED_DATA_PRODUCTS_BLOCK_RE.search(yaml_content):
        return _RELATED_DATA_PRODUCTS_BLOCK_RE.sub(block, yaml_content, count=1)
    if _DATA_PRODUCT_TYPE_RE.search(yaml_content):
        return _DATA_PRODUCT_TYPE_RE.sub(
            lambda m: f"{m.group(0)}\n{block.rstrip()}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{block}"


def _metric_asset_section_bodies(md_text: str) -> list[str]:
    """Body of ``## Superset Golden Assets`` — Trino tables + Superset URNs for DataHub assets."""
    body = _extract_section_body(md_text, "superset golden")
    return [body] if body else []


def _extract_metric_dataset_rows(md_path: Path) -> list[dict[str, str]]:
    """Extract Trino ``schema.table`` refs and Superset URNs for metric Data Product assets.

    Both are linked on the product Summary in DataHub (e.g. nps-fr: sandbox tables + Superset
    virtual datasets). Parsed from ``## Superset Golden Assets``.
    """
    rows: list[dict[str, str]] = []
    seen_tables: set[tuple[str, str]] = set()
    seen_urns: set[str] = set()
    for body in _metric_asset_section_bodies(md_path.read_text()):
        for schema, table in _TRINO_TABLE_REF_RE.findall(body):
            key = (schema.lower(), table.lower())
            if key not in seen_tables:
                seen_tables.add(key)
                rows.append({"schema": schema, "table": table})
        for urn in _SUPERSET_DATASET_URN_RE.findall(body):
            urn = urn.strip()
            if urn not in seen_urns:
                seen_urns.add(urn)
                rows.append({"urn": urn})
    return rows


def _as_yaml_datasets_block(rows: list[dict[str, str]]) -> str:
    lines = ["datasets:"]
    for row in rows:
        if row.get("urn"):
            lines.append(f"  - urn: {json.dumps(row['urn'])}")
        elif row.get("schema") and row.get("table"):
            lines.append(f"  - schema: {row['schema']}")
            lines.append(f"    table: {row['table']}")
    return "\n".join(lines) + "\n"


def _inject_metric_datasets(yaml_content: str, md_path: Path) -> str:
    """Replace ``datasets:`` with Trino + Superset reference assets extracted from the MD."""
    rows = _extract_metric_dataset_rows(md_path)
    yaml_content = _DATASETS_BLOCK_RE.sub("", yaml_content)
    if not rows:
        return yaml_content
    block = _as_yaml_datasets_block(rows)
    if _DATA_PRODUCT_TYPE_RE.search(yaml_content):
        return _DATA_PRODUCT_TYPE_RE.sub(
            lambda m: f"{m.group(0)}\n{block.rstrip()}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{block}"


def _inject_lifecycle_stage(yaml_content: str, default: str = "prod") -> str:
    """Ensure lifecycle_stage is present; inject default if the LLM omitted it.

    Only injects when the field is absent — never overrides a value the LLM emitted
    (e.g. draft, review, deprecated).
    """
    if _LIFECYCLE_STAGE_LINE_RE.search(yaml_content):
        return yaml_content  # already present
    line = f"lifecycle_stage: {default}"
    if _DOMAIN_URN_LINE_RE.search(yaml_content):
        return _DOMAIN_URN_LINE_RE.sub(
            lambda m: f"{m.group(0)}\n{line}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{line}\n"


def _inject_data_product_type(yaml_content: str, data_product_type: str) -> str:
    """Replace existing data_product_type line, or insert it after lifecycle_stage.

    Mirrors the surgical-replacement approach used by _inject_description so that
    the LLM output (which copies 'domain' from the gold standard) is always
    overridden with the correct value derived from the source directory.
    """
    line = f"data_product_type: {data_product_type}"
    if _DATA_PRODUCT_TYPE_RE.search(yaml_content):
        return _DATA_PRODUCT_TYPE_RE.sub(line, yaml_content, count=1)
    if _LIFECYCLE_STAGE_LINE_RE.search(yaml_content):
        return _LIFECYCLE_STAGE_LINE_RE.sub(
            lambda m: f"{m.group(0)}\n{line}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{line}\n"


def _ci_yaml_dir() -> Path:
    global _CI_YAML_DIR
    if _CI_YAML_DIR is None:
        override = os.environ.get("DATAHUB_CI_YAML_DIR", "").strip()
        _CI_YAML_DIR = (
            Path(override)
            if override
            else Path(tempfile.mkdtemp(prefix="datahub-ci-yaml-"))
        )
        _CI_YAML_DIR.mkdir(parents=True, exist_ok=True)
    return _CI_YAML_DIR


def _check_no_slug_collisions(paths: list[Path]) -> None:
    """Two MDs with the same stem → one Data Product URN, which is ambiguous. Fail loud."""
    seen: dict[str, Path] = {}
    for p in paths:
        slug = md_path_to_data_product_id(p)
        if slug in seen and seen[slug] != p:
            print(
                f"ERROR: slug collision — {seen[slug].name} and {p.name} both map to "
                f"data_product_id {slug!r}. Rename one.",
                file=sys.stderr,
            )
            sys.exit(1)
        seen[slug] = p


def _all_mds() -> list[Path]:
    found: list[Path] = []
    for d in _MD_DIRS:
        if d.is_dir():
            found.extend(p for p in d.glob("*.md") if not p.name.startswith("_"))
    found = sorted(found, key=lambda p: p.name)
    _check_no_slug_collisions(found)
    return found


def _git_changed_files() -> list[str]:
    """Return repo-relative paths changed in the current CI commit."""
    prev_sha = os.environ.get("CI_PREV_COMMIT_SHA", "").strip()
    curr_sha = os.environ.get("CI_COMMIT_SHA", "HEAD").strip() or "HEAD"

    if prev_sha:
        cmd = ["git", "diff", "--name-only", prev_sha, curr_sha]
    else:
        cmd = ["git", "diff", "--name-only", "HEAD~1", "HEAD"]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, cwd=_REPO_ROOT
        )
    except subprocess.CalledProcessError:
        result = subprocess.run(
            ["git", "show", "--name-only", "--format=", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            cwd=_REPO_ROOT,
        )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _changed_mds() -> list[Path]:
    changed = [
        _REPO_ROOT / f
        for f in _git_changed_files()
        if f.startswith(_MD_PREFIXES)
        and f.endswith(".md")
        and not Path(f).name.startswith("_")
    ]
    _check_no_slug_collisions(changed)
    return changed


def _loader_changed_in_commit() -> bool:
    return _LOADER_REL in _git_changed_files()


def _resolve_targets(args: argparse.Namespace) -> list[Path]:
    if args.all:
        return _all_mds()
    if args.resync_if_loader_changed and _loader_changed_in_commit():
        print("Loader changed in this commit — re-syncing all entity MDs.")
        return _all_mds()
    if args.md_paths:
        resolved: list[Path] = []
        for arg in args.md_paths:
            p = Path(arg)
            if not p.is_absolute():
                p = _REPO_ROOT / p
            if not p.exists():
                print(f"ERROR: file not found: {p}", file=sys.stderr)
                sys.exit(1)
            if p.name.startswith("_"):
                print(f"SKIP: {p.name} is a template file.")
                continue
            resolved.append(p)
        return resolved
    return _changed_mds()


def _stable_urn_for_query(entity_slug: str, index: int) -> str:
    """Deterministic per-query URN. Index 0 keeps the legacy ``uuid5(slug)`` value so the
    first golden query per product retains its existing URN (no re-creation churn)."""
    key = entity_slug if index == 0 else f"{entity_slug}:{index}"
    return f"urn:li:query:{uuid.uuid5(_URN_NAMESPACE, key)}"


def _enforce_stable_urns(yaml_content: str, entity_slug: str) -> str:
    """Overwrite every ``stable_urn:`` line in document order with its index-based URN.

    Works for both singular ``golden_query:`` (one line) and plural ``golden_queries:``
    (N lines) YAML — position in the text matches position in the list. The LLM emits
    ``"TBD"`` placeholders; CI is the authority for these URNs.
    """
    counter = {"i": 0}

    def _repl(m: re.Match) -> str:
        urn = _stable_urn_for_query(entity_slug, counter["i"])
        counter["i"] += 1
        return f"{m.group(1)}{urn}"

    return _STABLE_URN_LINE_RE.sub(_repl, yaml_content)


def _should_exclude_heading(line: str) -> bool:
    return any(p.match(line.strip()) for p in EXCLUDE_HEADING_PATTERNS)


def _extract_description_from_md(md_path: Path) -> str:
    """Full MD body minus Tables / Synonyms / Golden Queries / DataHub-catalog sections.

    This is the single source of truth for the Data Product description — the LLM no
    longer authors it (see SKILL.md step 2). Mirrors the audit-proven extraction logic.
    """
    lines = md_path.read_text().split("\n")
    result: list[str] = []
    skip = False
    for line in lines:
        if line.startswith("## "):
            skip = _should_exclude_heading(line)
        if not skip:
            result.append(line)
    content = "\n".join(result).strip()
    return re.sub(r"\n{3,}", "\n\n", content)


def _as_yaml_literal_block(key: str, value: str) -> str:
    """Render ``key: |`` literal block scalar with every line indented two spaces.

    Literal blocks need no escaping (markdown ``#``, ``:``, quotes, etc. are all safe),
    so this round-trips arbitrary MD content without mangling — unlike ``yaml.dump``.
    """
    indented = "\n".join((f"  {ln}" if ln else "") for ln in value.split("\n"))
    return f"{key}: |\n{indented}\n"


def _inject_description(yaml_content: str, description: str) -> str:
    """Replace (or insert) ``product_description`` with the full MD-derived text.

    Targeted string surgery — never a full ``yaml.dump`` round-trip — so multiline
    ``sql:`` blocks and key ordering survive untouched. Falls back to the original text
    (with a warning) if the result would not parse, so a valid YAML is never corrupted.
    """
    block = _as_yaml_literal_block("product_description", description)

    if _PRODUCT_DESCRIPTION_BLOCK_RE.search(yaml_content):
        candidate = _PRODUCT_DESCRIPTION_BLOCK_RE.sub(
            lambda _m: block, yaml_content, count=1
        )
    elif _PRODUCT_DISPLAY_NAME_LINE_RE.search(yaml_content):
        candidate = _PRODUCT_DISPLAY_NAME_LINE_RE.sub(
            lambda m: f"{m.group(0)}\n{block.rstrip()}", yaml_content, count=1
        )
    else:
        # No anchor — prepend after the kind line is impossible to locate reliably;
        # append at end so the loader at least sees a non-empty description.
        candidate = f"{yaml_content.rstrip()}\n{block}"

    try:
        parsed = yaml.safe_load(candidate)
    except yaml.YAMLError as err:
        print(
            f"   WARN: description injection produced invalid YAML ({err}); "
            "keeping LLM-authored description.",
            file=sys.stderr,
        )
        return yaml_content
    if (
        not isinstance(parsed, dict)
        or not str(parsed.get("product_description") or "").strip()
    ):
        print(
            "   WARN: description injection did not yield a non-empty "
            "product_description; keeping LLM-authored description.",
            file=sys.stderr,
        )
        return yaml_content
    return candidate


def _yaml_domain_urn(yaml_content: str) -> str:
    doc = yaml.safe_load(yaml_content)
    if not isinstance(doc, dict):
        return ""
    return str(doc.get("domain_urn") or "").strip()


def _validate_domain_urn(
    domain_urn: str,
    *,
    catalog_urns: frozenset[str],
    graphql_url: str,
    token: str,
) -> str | None:
    if not domain_urn.startswith("urn:li:domain:"):
        return f"domain_urn must start with urn:li:domain:, got {domain_urn!r}"

    if domain_urn in catalog_urns or entity_exists(graphql_url, token, domain_urn):
        return None

    sample = ", ".join(sorted(catalog_urns)[:8])
    suffix = "…" if len(catalog_urns) > 8 else ""
    return (
        f"domain_urn {domain_urn!r} not found in live DataHub catalog "
        f"({len(catalog_urns)} domains fetched). Examples: {sample}{suffix}"
    )


def _build_entity_rules(
    md_path: Path,
    *,
    entity_slug: str,
    domains_block: str,
    domain_count: int,
) -> str:
    data_product_type = _md_to_data_product_type(md_path)
    doc_link = _documentation_link(md_path, md_path.stem)
    related_ids = _extract_related_data_products(md_path)

    common = f"""- Infer domain_urn from the entity Markdown: pick exactly ONE domain from the
  LIVE DATAHUB CATALOG below. Copy the URN verbatim — do NOT invent slugs.
  Choose the domain whose name and description best match the entity's scope.

LIVE DATAHUB DOMAIN CATALOG ({domain_count} domains):
{domains_block}

- Emit ALL golden queries from the Markdown as a `golden_queries:` list (plural).
  Domain docs may use `## Golden query: {{Name}}` (singular H2) or `## Golden Queries`
  with `###` sub-headings; metric docs use `## Golden Queries`. For EACH query set
  `stable_urn: "TBD"` — CI assigns the real deterministic URN per query.
  Do NOT generate UUIDs yourself.
- Glossary term `id` values must match existing DataHub term slugs when the term
  already exists; the loader resolves by display name as fallback.
- Do NOT hand-author `product_description`. CI overwrites it with the full Markdown body
  (minus asset-routing, glossary, golden-query, catalog, and upstream-entity sections).
  Emit a one-line placeholder, e.g. `product_description: "(injected by CI from Markdown)"`.
- Set `data_product_type: {data_product_type}` and `lifecycle_stage: prod` unless the
  Markdown clearly indicates draft/review/deprecated.
- Use `structured_property.qualified_name: br.com.quintoandar.datahub.data_product.golden_query`
  and legacy drops `br.com.quintoandar.datahub.{entity_slug}.golden_query` /
  `...golden_query_url`.
- Set `documentation_link` exactly to:
    label: {doc_link["label"]!r}
    url: {doc_link["url"]}
- Output ONLY the YAML. No markdown fences, no commentary."""

    if data_product_type == "metric":
        related_rule = ""
        if related_ids:
            related_rule = (
                "\n- Set `related_data_products` to this list (CI also injects from MD):\n"
                + "".join(f"    - {pid}\n" for pid in related_ids)
            )
        metric_rows = _extract_metric_dataset_rows(md_path)
        asset_rule = ""
        if metric_rows:
            asset_rule = (
                "\n- CI injects reference assets from `## Superset Golden Assets` into `datasets:` "
                "(Trino `schema`/`table` rows + Superset `urn:` rows). Example:\n"
            )
            for row in metric_rows:
                if row.get("urn"):
                    asset_rule += f"    - urn: {row['urn']}\n"
                else:
                    asset_rule += (
                        f"    - schema: {row['schema']}\n      table: {row['table']}\n"
                    )
        return (
            common
            + f"""
- This is a **metric entity** (`docs/llm_context/metric_entities/`). Follow the metric
  template: thin on schema, thick on calculation.
- `## Superset Golden Assets` lists **reference assets** linked on the Data Product Summary in
  DataHub: Trino/Databricks `schema.table` pairs (materialized metric tables) AND Superset
  virtual-dataset URNs (in backticks). CI injects both into `datasets:` — do not drop either.{asset_rule}
- Parse glossary from `## Glossary and Synonyms` bullet list (`- **term** → mapping`).
- Do NOT hand-author `related_data_products` — CI injects from `## Related Business Entities`.{related_rule}"""
        )

    return (
        common
        + """
- This is a **domain entity** (`docs/llm_context/business_entities/`). Follow the business
  template: table routing + canonical golden query.
- Parse glossary from `## Synonyms` table (Term | Meaning | Notes) OR bullet list if present.
- In `datasets`, include only concrete `schema.table` pairs from `## Where to query what`
  (and per-schema table sections) that this product is the PRIMARY OWNER of. A table you
  only JOIN to but that another product owns belongs in the description prose, NOT in
  `datasets` — listing it would steal it from the other product (assignment is exclusive).
  Never use wildcards (`*`), schema globs (`schema.*`), or placeholder patterns
  (`statement_*`, `reverse_accounts_*`). Omit patterns; expand to explicit names or skip.
- Do NOT emit `related_data_products` (domain products only)."""
    )


def _build_messages(
    md_path: Path,
    *,
    domains: list[DataHubDomain],
) -> list[dict]:
    skill_text = _SKILL_MD.read_text()
    md_text = md_path.read_text()
    gold_text = _GOLD_STANDARD.read_text() if _GOLD_STANDARD.exists() else ""
    glossary_text = _GLOSSARY_EXAMPLE.read_text() if _GLOSSARY_EXAMPLE.exists() else ""

    rel_md = md_path.relative_to(_REPO_ROOT)
    entity_slug = md_path_to_data_product_id(md_path)
    domains_block = format_domains_for_prompt(domains)
    entity_rules = _build_entity_rules(
        md_path,
        entity_slug=entity_slug,
        domains_block=domains_block,
        domain_count=len(domains),
    )

    system = (
        "You are a data engineer at QuintoAndar. "
        "Your task is to convert a business or metric entity Markdown file into a DataHub YAML. "
        "Output ONLY the raw YAML content — no markdown fences, no commentary, "
        "no explanation. The entire response must be valid YAML that can be written "
        "directly to a file."
    )

    user = f"""Follow the instructions in the SKILL below to generate the DataHub YAML.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SKILL: md-to-datahub-yaml
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{skill_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GOLD STANDARD REFERENCE (reference/payments.datahub.yaml)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{gold_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GLOSSARY related_terms EXAMPLE (reference/visits.datahub.yaml)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{glossary_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INPUT: {rel_md}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{md_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FIXED INPUTS (use these verbatim — do not change):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- data_product_id : {entity_slug}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RULES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{entity_rules}
"""

    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


def _extract_yaml(response_text: str) -> str:
    fenced = re.match(r"^```(?:yaml)?\n(.*?)```\s*$", response_text.strip(), re.DOTALL)
    if fenced:
        return fenced.group(1)
    return response_text.strip()


_CHAT_COMPLETIONS_PATH = "/chat/completions"
_TIMEOUT_SECONDS = 120
_LLM_MAX_ATTEMPTS = 3
_LLM_RETRYABLE_STATUS = frozenset({429, 502, 503, 504})


def _call_llm(messages: list[dict], model: str, base_url: str, api_key: str) -> str:
    payload = {"model": model, "messages": messages}
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    url = f"{base_url.rstrip('/')}{_CHAT_COMPLETIONS_PATH}"
    last_error: Exception | None = None

    for attempt in range(1, _LLM_MAX_ATTEMPTS + 1):
        try:
            response = requests.post(
                url,
                headers=headers,
                json=payload,
                timeout=_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            break
        except requests.HTTPError as err:
            last_error = err
            status = err.response.status_code if err.response is not None else None
            if status not in _LLM_RETRYABLE_STATUS or attempt >= _LLM_MAX_ATTEMPTS:
                raise
            delay_s = 2**attempt
            print(
                f"   WARN: LiteLLM HTTP {status} — retry {attempt}/{_LLM_MAX_ATTEMPTS - 1} "
                f"in {delay_s}s",
                file=sys.stderr,
            )
            time.sleep(delay_s)
        except requests.RequestException as err:
            last_error = err
            if attempt >= _LLM_MAX_ATTEMPTS:
                raise
            delay_s = 2**attempt
            print(
                f"   WARN: LiteLLM request failed — retry {attempt}/{_LLM_MAX_ATTEMPTS - 1} "
                f"in {delay_s}s ({err})",
                file=sys.stderr,
            )
            time.sleep(delay_s)
    else:
        assert last_error is not None
        raise last_error

    body = response.json()
    choices = body.get("choices") or []
    if not choices:
        raise ValueError(f"LiteLLM response contained no choices. Raw: {body}")

    content = (choices[0].get("message") or {}).get("content")
    if isinstance(content, str) and content.strip():
        return content
    if isinstance(content, list):
        text = "".join(
            p.get("text", "")
            for p in content
            if isinstance(p, dict) and p.get("type") == "text"
        ).strip()
        if text:
            return text

    raise ValueError(f"LiteLLM response contained no text content. Raw: {body}")


def _push_to_datahub(yaml_path: Path) -> int:
    proc = subprocess.run(
        ["uv", "run", "python", str(_LOADER), "--config", str(yaml_path)],
        check=False,
        cwd=_REPO_ROOT,
    )
    return proc.returncode


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate ephemeral DataHub YAML from entity Markdown and push to DataHub.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Process every entity MD under docs/llm_context/business_entities/",
    )
    parser.add_argument(
        "--resync-if-loader-changed",
        action="store_true",
        help=(
            "When load_collections_context.py changed in this commit, process all MDs; "
            "otherwise only MDs changed in this commit."
        ),
    )
    parser.add_argument(
        "md_paths",
        nargs="*",
        help="Explicit MD paths (local testing). Overrides git diff unless --all is set.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    targets = _resolve_targets(args)
    if not targets:
        print("No entity MD files to process — skipping DataHub publication.")
        return 0

    model = os.environ.get("LITELLM_MODEL", _DEFAULT_MODEL).strip()
    base_url = os.environ.get("LITELLM_BASE_URL", _DEFAULT_BASE_URL).strip()
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    datahub_url = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
    datahub_token = os.environ.get("DATAHUB_TOKEN", "").strip()

    if not api_key:
        print("ERROR: OPENAI_API_KEY is not set.", file=sys.stderr)
        return 1
    if not datahub_url:
        print("ERROR: DATAHUB_GRAPHQL_URL is not set.", file=sys.stderr)
        return 1
    if not datahub_token:
        print("ERROR: DATAHUB_TOKEN is not set.", file=sys.stderr)
        return 1

    domains = fetch_all_domains(datahub_url, datahub_token)
    if not domains:
        print(
            "ERROR: DataHub returned zero domains — cannot infer domain_urn safely.",
            file=sys.stderr,
        )
        return 1

    catalog_urns = known_domain_urns(domains)
    yaml_dir = _ci_yaml_dir()
    print(f"Model          : {model}")
    print(f"LiteLLM proxy  : {base_url}")
    print(f"DataHub target : {datahub_url}")
    print(f"Domains loaded : {len(domains)} (live catalog from DataHub)")
    print(f"YAML workspace : {yaml_dir} (ephemeral, not committed)")
    print(f"Entities found : {len(targets)}")
    print("─" * 60)

    passed: list[str] = []
    failed: list[str] = []

    for md_path in targets:
        entity_slug = md_path_to_data_product_id(md_path)
        yaml_path = yaml_dir / f"{entity_slug}.datahub.yaml"

        print(f"\n▶  {entity_slug}")
        print(f"   query 0 urn : {_stable_urn_for_query(entity_slug, 0)} (uuid5)")

        try:
            messages = _build_messages(md_path, domains=domains)
            raw = _call_llm(messages, model, base_url, api_key)
        except Exception as err:
            print(f"   ERROR: LLM call failed — {err}", file=sys.stderr)
            failed.append(entity_slug)
            continue

        yaml_content = _extract_yaml(raw)
        if not yaml_content.startswith("spec_version:"):
            print(
                f"   ERROR: LLM response does not look like a valid DataHub YAML "
                f"(first chars: {yaml_content[:80]!r})",
                file=sys.stderr,
            )
            failed.append(entity_slug)
            continue

        yaml_content = _enforce_stable_urns(yaml_content, entity_slug)
        yaml_content = _inject_description(
            yaml_content, _extract_description_from_md(md_path)
        )
        yaml_content = _inject_lifecycle_stage(yaml_content)
        yaml_content = _inject_data_product_type(
            yaml_content, _md_to_data_product_type(md_path)
        )
        yaml_content = _inject_documentation_link(
            yaml_content, _documentation_link(md_path, md_path.stem)
        )
        if _md_to_data_product_type(md_path) == "metric":
            yaml_content = _inject_metric_datasets(yaml_content, md_path)
            yaml_content = _inject_related_data_products(
                yaml_content, _extract_related_data_products(md_path)
            )

        domain_err = _validate_domain_urn(
            _yaml_domain_urn(yaml_content),
            catalog_urns=catalog_urns,
            graphql_url=datahub_url,
            token=datahub_token,
        )
        if domain_err:
            print(f"   ERROR: {domain_err}", file=sys.stderr)
            failed.append(entity_slug)
            continue

        yaml_path.write_text(yaml_content + "\n")
        print(f"   ✓ YAML written ({yaml_path.stat().st_size} bytes). Publishing…")

        exit_code = _push_to_datahub(yaml_path)
        if exit_code != 0:
            print(f"   ✗ DataHub push failed (exit {exit_code})", file=sys.stderr)
            failed.append(entity_slug)
        else:
            print("   ✓ Published to DataHub.")
            passed.append(entity_slug)

    total = len(targets)
    print(f"\n{'═' * 60}")
    print(f"Results: {len(passed)} passed / {len(failed)} failed / {total} total")

    if passed:
        print("\nPublished:")
        for name in passed:
            print(f"  ✓ {name}")

    if failed:
        print("\nFailed:", file=sys.stderr)
        for name in failed:
            print(f"  ✗ {name}", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
