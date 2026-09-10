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
  domain — domain_entities/*.md: table routing, Synonyms, owned datasets
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
    LITELLM_MAX_TOKENS   — override the default output token ceiling (16000);
                            raise this for entities with many/large golden
                            queries to avoid mid-YAML truncation (see
                            _count_expected_golden_queries)
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
        docs/llm_context/domain_entities/my_entity.md

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
    _REPO_ROOT / "docs/llm_context/domain_entities",
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
# Golden-query headings in the source Markdown, used to detect incomplete LLM
# output (see _count_expected_golden_queries / _count_golden_queries_in_yaml).
_GOLDEN_QUERY_SINGULAR_HEADING_RE = re.compile(r"^## Golden [Qq]uery:\s*\S", re.M)
_GOLDEN_QUERY_SECTION_HEADING_RE = re.compile(r"^## Golden [Qq]uer(y|ies)\b")
# Sub-heading naming within a "## Golden Queries" section is inconsistent across
# the ~50 existing entity docs ("### Query 1 — ...", "### 1. ...", or a bare
# descriptive title with no numbering) and some entities append trailing
# non-query sub-sections (e.g. "### Validation") — so heading text can't
# reliably identify a query. Every query, regardless of heading style, has
# exactly one fenced ```sql block (see gold-standard reference and every
# existing doc); count those instead.
_SQL_FENCE_OPEN_RE = re.compile(r"^```sql\s*$", re.I)
_SQL_FENCE_CLOSE_RE = re.compile(r"^```\s*$")
# Matches a ``sql:`` key at any indentation (top-level, or nested inside a
# ``golden_query:`` mapping / ``golden_queries:`` list item) — used to locate and
# overwrite each golden query's SQL text with the raw Markdown source (see
# _inject_golden_query_sqls). Captures the key's own leading whitespace so the
# caller can tell where its value block ends (any subsequent line indented no
# more than this key).
_SQL_KEY_LINE_RE = re.compile(r"^([ \t]*)sql:")

_DEFAULT_MODEL = "openai/gpt-5.3-codex"
_DEFAULT_BASE_URL = "https://litellm.apps.shared-prd.habitat.zone/v1"
# Generous ceiling so entities with many/large golden queries (e.g. 9 full SQL
# blocks) don't get silently truncated mid-YAML by the model's own default cap.
# Override per-run with LITELLM_MAX_TOKENS if an entity still needs more.
_DEFAULT_MAX_TOKENS = 16000

# Markdown ``## `` sections that must NOT be folded into the Data Product description.
# Aligned with docs/llm_context/{business,metric}_entities/_TEMPLATE.md:
#   both    — Ownership → routing metadata only, never narrative content (Data Owner /
#             Data Steward emails must not leak into the public Data Product description)
#   domain  — Where to query what → datasets; Synonyms → glossary; Golden query(ies) → Query entities
#   metric  — Related Domain Entities → related_data_products SP; Glossary → glossary;
#             Golden Queries → Query entities; DataHub Catalog → tooling pointer only;
#             MBR → data_product.mbr / data_product.mbr_category structured properties;
#             Catalog → data_product.metrics structured property, one entry per metric
#             with its OKR/Health Metric type embedded (e.g. "NPS True (OKR)") — a row
#             missing a valid type fails the entity instead of publishing unclassified
#             (see _validate_catalog_types) — none of these are narrative content
#   metric  — Targets and OKRs is intentionally NOT listed here: Budget/OKR lookup
#             guidance stays in product_description (narrative content for downstream agents)
EXCLUDE_HEADING_PATTERNS = [
    re.compile(r"^## Ownership$", re.I),
    re.compile(r"^## MBR$", re.I),
    re.compile(r"^## Catalog$", re.I),
    re.compile(r"^## (Tables|Where to query what)$", re.I),
    re.compile(r"^## (Synonyms|Glossary and Synonyms)$", re.I),
    re.compile(r"^## Golden [Qq]uer(y|ies)\b.*$", re.I),
    re.compile(r"^## DataHub [Cc]atalog$"),
    re.compile(r"^## Related Domain Entities$", re.I),
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
_SUPERSET_ASSET_URN_RE = re.compile(
    r"urn:li:dataset:\(urn:li:dataPlatform:superset,[^)]+\)"
    r"|urn:li:chart:\(superset,[^)]+\)"
    r"|urn:li:dashboard:\(superset,[^)]+\)",
    re.I,
)
_TRINO_TABLE_REF_RE = re.compile(r"`([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)`")

# Ownership parsing (## Ownership section → owners: block in the YAML).
# Only real @quintoandar.com / @quintoandar.com.br addresses match — template
# placeholders such as ``{data_owner_email@quintoandar.com.br}`` are ignored
# (the leading ``{`` breaks the match).
_OWNER_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@quintoandar\.com(?:\.br)?$")
# The two bold sub-groups inside ``## Ownership``; each maps to a DataHub ownership type.
_OWNER_ROLE_HEADINGS = {
    "data owner": "data_owner",
    "data steward": "data_steward",
}
_OWNER_ROLE_HEADING_RE = re.compile(r"^\*\*\s*(.+?)\s*:\s*\*\*$")
_OWNERS_BLOCK_RE = re.compile(r"(?ms)^owners:.*?\n(?=\S|\Z)")
_MAILTO_LINK_RE = re.compile(r"^\[([^\]]+)\]\(mailto:[^)]+\)$", re.IGNORECASE)

# MBR parsing (## MBR section → mbr: list block in the YAML, metric entities only).
# Template placeholders such as ``{MBR Name}`` are ignored (the braces break the match).
_MBR_BLOCK_RE = re.compile(r"(?ms)^mbr:.*?\n(?=\S|\Z)")
# ``**Name** Post Contract`` / ``**Category:** Quality`` — the colon may sit inside or
# outside the bold wrap, or be absent entirely (the authoring template omits it).
_MBR_FIELD_RE = re.compile(
    r"^\*{2,3}\s*(name|category)\s*:?\s*\*{2,3}\s*:?\s*(.*)$", re.I
)

# Catalog parsing (## Catalog table → catalog: list block in the YAML, metric entities
# only). Rows are ``| {Metric Name} | {OKR | Health Metric} |``; the header and the
# ``|---|`` separator are skipped, as are unfilled ``{...}`` template placeholders.
_CATALOG_BLOCK_RE = re.compile(r"(?ms)^catalog:.*?\n(?=\S|\Z)")
_CATALOG_TYPE_OKR = "OKR"
_CATALOG_TYPE_HEALTH = "Health Metric"
# Canonical spelling per lowercased alias, so ``okr`` / ``health metric`` / ``health``
# authored in any case all land on one filterable structured-property value.
_CATALOG_TYPE_ALIASES = {
    "okr": _CATALOG_TYPE_OKR,
    "health metric": _CATALOG_TYPE_HEALTH,
    "health": _CATALOG_TYPE_HEALTH,
}


def md_path_to_data_product_id(md_path: Path) -> str:
    """``accounting_funnel.md`` → ``accounting-funnel``."""
    return md_path.stem.replace("_", "-")


def _md_to_data_product_type(md_path: Path) -> str:
    """Return 'metric' for metric_entities/, 'domain' for everything else."""
    return "metric" if "metric_entities" in md_path.parts else "domain"


def _llm_context_subdir(md_path: Path) -> str:
    return (
        "metric_entities" if "metric_entities" in md_path.parts else "domain_entities"
    )


def _display_name_to_product_id(name: str) -> str:
    """``NPS`` → ``nps``; ``House and Listing`` → ``house-and-listing``."""
    return re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")


def _normalize_heading(text: str) -> str:
    """Strip Markdown emphasis and collapse whitespace for heading comparisons."""
    cleaned = re.sub(r"[*_`]+", "", text)
    return re.sub(r"\s+", " ", cleaned).strip().lower()


def _extract_section_body(
    md_text: str, *heading_substrings: str, exact_only: bool = False
) -> str:
    """Return the body of the best-matching ``##`` section.

    Exact heading matches (after stripping emphasis) win over substring matches so
    ``## Pre-ownership`` cannot steal an ``ownership`` lookup from ``## Ownership``.
    ``exact_only`` disables the substring fallback entirely — required for ``catalog``,
    where the unrelated ``## DataHub Catalog`` section would otherwise match.
    """
    lines = md_text.splitlines()
    exact_body: list[str] | None = None
    substring_body: list[str] | None = None
    mode: str | None = None  # "exact" | "substring" | None
    current: list[str] = []

    def _flush() -> None:
        nonlocal exact_body, substring_body, mode, current
        if mode == "exact" and exact_body is None:
            exact_body = current
        elif mode == "substring" and substring_body is None:
            substring_body = current
        mode = None
        current = []

    for line in lines:
        if line.startswith("## "):
            _flush()
            title = _normalize_heading(line[3:])
            for sub in heading_substrings:
                cand = sub.strip().lower()
                if title == cand:
                    mode = "exact"
                    break
                if cand in title and mode is None:
                    mode = "substring"
            continue
        if mode is not None:
            current.append(line)
    _flush()
    if exact_only:
        return "\n".join(exact_body or []).strip()
    chosen = exact_body if exact_body is not None else substring_body
    return "\n".join(chosen or []).strip()


def _extract_related_data_products(md_path: Path) -> list[str]:
    """Parse ``## Related Domain Entities`` bullets into kebab-case product IDs."""
    section = _extract_section_body(md_path.read_text(), "related domain entities")
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


def _count_expected_golden_queries(md_path: Path) -> int:
    """Count golden queries declared in the source Markdown.

    A golden-query zone is opened by either heading style — a repeated
    ``## Golden query: {Name}`` (domain docs, one H2 per query) or the plural
    ``## Golden Queries`` H2 (metric docs, and most domain docs) — and stays open
    across any H3 sub-headings until the next H2. Every query, regardless of
    heading style, has exactly one fenced ```sql block, so count those rather than
    relying on heading text (inconsistent across ~50 existing docs — numbered,
    unnumbered, or a bare title — and some entities append a trailing non-query
    sub-section like "### Validation"). Returns 0 when no golden queries section
    is present (entity legitimately has none yet).

    A single ``## Golden query: {Name}`` heading can itself contain more than one
    query as H3 sub-sections (e.g. ``agents.md``: "Active agents per hub" plus two
    "### Reconciliation ..." / "### CIQ portfolio loss ..." sub-queries under it) —
    treating the heading as a hard count of 1 undercounts those and lets a
    truncated LLM response that emits only the first query pass the completeness
    check below.

    Used by ``main()`` to catch a truncated/incomplete LLM response before it gets
    published: the Cases Perspective incident had 9 queries here but only 2 reached
    DataHub with nothing detecting the gap.
    """
    lines = md_path.read_text().splitlines()

    in_section = False
    count = 0
    for line in lines:
        if _GOLDEN_QUERY_SINGULAR_HEADING_RE.match(
            line
        ) or _GOLDEN_QUERY_SECTION_HEADING_RE.match(line):
            in_section = True
            continue
        if in_section and line.startswith("## "):
            in_section = False
            continue
        if in_section and _SQL_FENCE_OPEN_RE.match(line.strip()):
            count += 1
    return count


def _count_golden_queries_in_yaml(yaml_content: str) -> int:
    """Count ``stable_urn:`` placeholders — one per golden query — in generated YAML."""
    return len(_STABLE_URN_LINE_RE.findall(yaml_content))


def _extract_golden_query_sqls(md_path: Path) -> list[str]:
    """Extract the raw SQL text of every golden query, in document order.

    Reuses the exact same golden-query-zone boundary logic as
    ``_count_expected_golden_queries`` (any golden heading opens a zone that stays
    open across H3 sub-headings until the next H2) — same count, same order — but
    captures the full text of each fenced ```sql block instead of just counting
    fence-open lines.

    This is the single source of truth injected into each generated
    ``golden_query(ies)[i].sql`` by ``_inject_golden_query_sqls``: the LLM is asked
    for a short placeholder instead of reproducing the (potentially large) query
    text, so the query text itself can never be truncated or paraphrased.
    """
    lines = md_path.read_text().splitlines()
    in_section = False
    in_fence = False
    current: list[str] = []
    sqls: list[str] = []
    for line in lines:
        if _GOLDEN_QUERY_SINGULAR_HEADING_RE.match(
            line
        ) or _GOLDEN_QUERY_SECTION_HEADING_RE.match(line):
            in_section = True
            continue
        if in_section and line.startswith("## "):
            in_section = False
            continue
        if in_section and not in_fence and _SQL_FENCE_OPEN_RE.match(line.strip()):
            in_fence = True
            current = []
            continue
        if in_fence and _SQL_FENCE_CLOSE_RE.match(line.strip()):
            in_fence = False
            sqls.append("\n".join(current).strip())
            continue
        if in_fence:
            current.append(line)
    return sqls


def _inject_golden_query_sqls(yaml_content: str, sqls: list[str]) -> str:
    """Overwrite every ``sql:`` value in document order with the raw SQL text
    extracted from the source Markdown (see ``_extract_golden_query_sqls``).

    The LLM is instructed (see ``_build_entity_rules``) to emit a short placeholder
    for ``sql:`` instead of reproducing the query text — that text is exactly what
    used to balloon LLM output tokens and risk truncation (the Cases Perspective
    incident). CI is the single source of truth for the actual SQL, so once this
    injection runs, the query text itself cannot be truncated, paraphrased, or
    otherwise altered by the LLM.

    Falls back to the LLM-authored content (with a warning) when the number of
    ``sql:`` keys found in the YAML doesn't match ``len(sqls)`` — a structural
    mismatch means the LLM didn't emit one golden query object per Markdown query
    (e.g. it dropped an entire entry), so blind position-based injection would
    silently attach the wrong SQL to the wrong query. That case is still caught
    by the existing ``_count_expected_golden_queries`` vs
    ``_count_golden_queries_in_yaml`` completeness check right after this call.
    """
    if not sqls:
        return yaml_content

    lines = yaml_content.split("\n")
    sql_line_idxs = [i for i, line in enumerate(lines) if _SQL_KEY_LINE_RE.match(line)]
    if len(sql_line_idxs) != len(sqls):
        print(
            f"   WARN: found {len(sql_line_idxs)} 'sql:' key(s) in the generated YAML "
            f"but {len(sqls)} golden querie(s) in the Markdown; keeping LLM-authored "
            "SQL text (position-based injection needs a 1:1 match).",
            file=sys.stderr,
        )
        return yaml_content

    # Walk back-to-front so replacing one block never shifts the line indices of
    # the ones still to be processed.
    for sql_idx, line_idx in reversed(list(enumerate(sql_line_idxs))):
        key_line = lines[line_idx]
        indent_match = _SQL_KEY_LINE_RE.match(key_line)
        indent = indent_match.group(1) if indent_match else ""

        end = line_idx + 1
        while end < len(lines):
            candidate = lines[end]
            if candidate.strip() == "":
                end += 1
                continue
            candidate_indent = candidate[
                : len(candidate) - len(candidate.lstrip(" \t"))
            ]
            if len(candidate_indent) <= len(indent):
                break
            end += 1

        block = _as_yaml_literal_block("sql", sqls[sql_idx], indent=indent)
        lines[line_idx:end] = block.rstrip("\n").split("\n")

    return "\n".join(lines)


def _extract_owners(md_path: Path) -> dict[str, list[str]]:
    """Parse ``## Ownership`` into ``{"data_owner": [...], "data_steward": [...]}``.

    Reads the two bold sub-groups (``**Data Owner:**`` / ``**Data Steward:**``) and the
    ``@quintoandar.com`` / ``@quintoandar.com.br`` email bullets under each.
    Template placeholders (wrapped in
    ``{...}``) never match and are silently dropped, so an unfilled template yields empty
    lists. Emails are de-duplicated per role, preserving document order.
    """
    section = _extract_section_body(md_path.read_text(), "ownership")
    owners: dict[str, list[str]] = {role: [] for role in _OWNER_ROLE_HEADINGS.values()}
    current_role: str | None = None
    for line in section.splitlines():
        stripped = line.strip()
        heading = _OWNER_ROLE_HEADING_RE.match(stripped)
        if heading:
            current_role = _OWNER_ROLE_HEADINGS.get(heading.group(1).strip().lower())
            continue
        if current_role is None or not stripped.startswith("- "):
            continue
        email = stripped[2:].strip()
        link_match = _MAILTO_LINK_RE.match(email)
        if link_match:
            email = link_match.group(1).strip()
        if _OWNER_EMAIL_RE.match(email) and email not in owners[current_role]:
            owners[current_role].append(email)
    return owners


def _as_yaml_owners_block(owners: dict[str, list[str]]) -> str:
    lines = ["owners:"]
    for role in _OWNER_ROLE_HEADINGS.values():
        emails = owners.get(role) or []
        if not emails:
            continue
        lines.append(f"  {role}:")
        lines.extend(f"    - {email}" for email in emails)
    return "\n".join(lines) + "\n"


def _inject_owners(yaml_content: str, owners: dict[str, list[str]]) -> str:
    """Insert (or replace) the ``owners:`` block with the emails parsed from the MD.

    Drops any LLM-authored ``owners:`` block first (the Markdown is the single source of
    truth). When no owner emails were parsed the block is omitted entirely — the loader
    treats a missing block as "no ownership to sync".
    """
    yaml_content = _OWNERS_BLOCK_RE.sub("", yaml_content)
    if not any(owners.get(role) for role in _OWNER_ROLE_HEADINGS.values()):
        return yaml_content
    block = _as_yaml_owners_block(owners)
    if _DATA_PRODUCT_TYPE_RE.search(yaml_content):
        return _DATA_PRODUCT_TYPE_RE.sub(
            lambda m: f"{m.group(0)}\n{block.rstrip()}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{block}"


def _is_placeholder(value: str) -> bool:
    """True for an unfilled authoring placeholder such as ``{MBR Name}`` or ``{category}``."""
    return not value or "{" in value or "}" in value


def _extract_mbrs(md_path: Path) -> list[dict[str, str]]:
    """Parse ``## MBR`` into a de-duplicated list of ``{name, category}`` (metric docs).

    Reads the ``**Name** {MBR name}`` / ``**Category** {category}`` pairs under
    ``## MBR``, repeated once per MBR when the document feeds several. The legacy
    ``- {MBR name}`` bullet form is still accepted (category omitted) so a document that
    has not been migrated yet keeps publishing its MBR membership. Template placeholders
    (wrapped in ``{...}``) are ignored, so an unfilled template yields an empty list.
    Entries are de-duplicated by name, case-insensitively, preserving document order.
    """
    section = _extract_section_body(md_path.read_text(), "mbr")
    entries: list[dict[str, str]] = []
    seen: set[str] = set()

    def _add(name: str, category: str = "") -> None:
        if _is_placeholder(name) or name.lower() in seen:
            return
        seen.add(name.lower())
        entry = {"name": name}
        if category and not _is_placeholder(category):
            entry["category"] = category
        entries.append(entry)

    pending_name: str | None = None
    for line in section.splitlines():
        stripped = line.strip()
        field = _MBR_FIELD_RE.match(stripped)
        if field:
            key, value = field.group(1).lower(), field.group(2).strip()
            if key == "name":
                if pending_name is not None:
                    _add(pending_name)
                pending_name = value
            elif pending_name is not None:
                _add(pending_name, value)
                pending_name = None
            continue
        if stripped.startswith("- "):
            _add(stripped[2:].strip().strip("*").strip())
    if pending_name is not None:
        _add(pending_name)
    return entries


def _inject_mbr(yaml_content: str, mbrs: list[dict[str, str]]) -> str:
    """Insert (or replace) the ``mbr:`` list block with the entries parsed from the MD.

    Drops any LLM-authored ``mbr:`` block first (the Markdown is the single source of
    truth). When no MBR entries were parsed the block is omitted entirely — the loader
    treats a missing block on a metric product as "clear MBR membership".
    """
    yaml_content = _MBR_BLOCK_RE.sub("", yaml_content)
    if not mbrs:
        return yaml_content
    lines = ["mbr:"]
    for entry in mbrs:
        lines.append(f"  - name: {json.dumps(entry['name'])}")
        if entry.get("category"):
            lines.append(f"    category: {json.dumps(entry['category'])}")
    block = "\n".join(lines) + "\n"
    if _DATA_PRODUCT_TYPE_RE.search(yaml_content):
        return _DATA_PRODUCT_TYPE_RE.sub(
            lambda m: f"{m.group(0)}\n{block.rstrip()}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{block}"


def _split_table_row(line: str) -> list[str]:
    """Split a Markdown table row into cells, honouring escaped pipes.

    A metric name may legitimately contain a pipe (``EC|ES2CS``), which Markdown
    requires the author to escape as ``EC\\|ES2CS``. Splitting naively on ``|`` would
    tear that name in half and shift every following cell.
    """
    cells = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [cell.replace(r"\|", "|").strip() for cell in cells]


def _normalize_catalog_type(raw: str) -> str:
    """Map an authored Type cell onto its canonical spelling (``OKR``/``Health Metric``).

    Unknown values are kept verbatim rather than dropped: the row still reaches DataHub,
    where a reviewer can see and correct it, instead of silently disappearing.
    """
    cleaned = re.sub(r"[*`]+", "", raw).strip()
    return _CATALOG_TYPE_ALIASES.get(cleaned.lower(), cleaned)


_CATALOG_VALID_TYPES = {_CATALOG_TYPE_OKR, _CATALOG_TYPE_HEALTH}


def _extract_catalog(md_path: Path) -> list[dict[str, str]]:
    """Parse the ``## Catalog`` table into ``{name, type}`` rows (metric docs).

    Reads the ``| Metric | Type |`` table: one row per official metric defined in the
    document. ``exact_only`` matching keeps the unrelated ``## DataHub Catalog`` section
    from being read as the catalog. Header/separator rows and unfilled ``{...}``
    placeholders are skipped; metrics are de-duplicated by name, case-insensitively.

    A metric row always keeps its ``type`` cell verbatim (normalized via
    ``_normalize_catalog_type``), even when it is missing or does not resolve to a
    recognized category — ``_validate_catalog_types`` below is the single place that
    turns an unclassified metric into a hard error, so every metric published to
    DataHub is unambiguously tagged ``OKR`` or ``Health Metric``.
    """
    section = _extract_section_body(md_path.read_text(), "catalog", exact_only=True)
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = _split_table_row(stripped)
        if len(cells) < 2 or set(cells[0]) <= {"-", ":", " "}:
            continue
        name = re.sub(r"[*`]+", "", cells[0]).strip()
        if _is_placeholder(name) or name.lower() in {"metric", "metrics"}:
            continue
        if name.lower() in seen:
            continue
        seen.add(name.lower())
        row = {"name": name}
        metric_type = _normalize_catalog_type(cells[1])
        if not _is_placeholder(metric_type):
            row["type"] = metric_type
        rows.append(row)
    return rows


def _validate_catalog_types(catalog: list[dict[str, str]]) -> list[str]:
    """Return the names of ``## Catalog`` metrics missing a valid OKR/Health Metric type.

    A metric with no ``type`` cell (or one that doesn't resolve to a recognized
    category) can no longer be published: ``curated_push_catalog`` embeds the type
    directly into each ``data_product.metrics`` value (e.g. ``"NPS True (OKR)"``), so
    an unclassified metric would either be silently dropped or published with a
    misleading blank category. Every metric must be classified at authoring time.
    """
    return [
        row["name"] for row in catalog if row.get("type") not in _CATALOG_VALID_TYPES
    ]


def _inject_catalog(yaml_content: str, catalog: list[dict[str, str]]) -> str:
    """Insert (or replace) the ``catalog:`` block with the rows parsed from the MD.

    Same "Markdown is the single source of truth" contract as ``owners:`` and ``mbr:``:
    any LLM-authored block is dropped first, and an empty catalog omits the block so the
    loader clears whatever the product had before.
    """
    yaml_content = _CATALOG_BLOCK_RE.sub("", yaml_content)
    if not catalog:
        return yaml_content
    lines = ["catalog:"]
    for row in catalog:
        lines.append(f"  - name: {json.dumps(row['name'])}")
        if row.get("type"):
            lines.append(f"    type: {json.dumps(row['type'])}")
    block = "\n".join(lines) + "\n"
    if _DATA_PRODUCT_TYPE_RE.search(yaml_content):
        return _DATA_PRODUCT_TYPE_RE.sub(
            lambda m: f"{m.group(0)}\n{block.rstrip()}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{block}"


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
    """Body of ``## Superset Golden Assets`` — Trino tables + Superset assets for DataHub."""
    body = _extract_section_body(md_text, "superset golden")
    return [body] if body else []


def _extract_metric_dataset_rows(md_path: Path) -> list[dict[str, str]]:
    """Extract Trino ``schema.table`` refs and Superset assets for metric Data Product assets.

    Both are linked on the product Summary in DataHub (e.g. nps-fr: sandbox tables + Superset
    virtual datasets / charts / dashboards). Parsed from ``## Superset Golden Assets``.
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
        for urn in _SUPERSET_ASSET_URN_RE.findall(body):
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


def _inject_datasets_block(yaml_content: str, rows: list[dict[str, str]]) -> str:
    """Replace the LLM ``datasets:`` block with CI-extracted rows (or drop it)."""
    yaml_content = _DATASETS_BLOCK_RE.sub("", yaml_content)
    if not rows:
        return yaml_content
    block = _as_yaml_datasets_block(rows)
    if _DATA_PRODUCT_TYPE_RE.search(yaml_content):
        return _DATA_PRODUCT_TYPE_RE.sub(
            lambda m: f"{m.group(0)}\n{block.rstrip()}", yaml_content, count=1
        )
    return yaml_content.rstrip() + f"\n{block}"


def _inject_metric_datasets(yaml_content: str, md_path: Path) -> str:
    """Replace ``datasets:`` with Trino + Superset reference assets extracted from the MD."""
    return _inject_datasets_block(yaml_content, _extract_metric_dataset_rows(md_path))


def _extract_domain_dataset_rows(md_path: Path) -> list[dict[str, str]]:
    """Extract ``schema.table`` refs from ``## Tables`` / ``## Where to query what``."""
    text = md_path.read_text()
    body = _extract_section_body(text, "tables", "where to query")
    source = body or text
    rows: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for schema, table in _TRINO_TABLE_REF_RE.findall(source):
        key = (schema.lower(), table.lower())
        if key not in seen:
            seen.add(key)
            rows.append({"schema": schema, "table": table})
    return rows


def _inject_domain_datasets(yaml_content: str, md_path: Path) -> str:
    """Replace ``datasets:`` with tables parsed from the domain entity Markdown."""
    return _inject_datasets_block(yaml_content, _extract_domain_dataset_rows(md_path))


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
    """MDs changed in the current CI commit that still exist on disk.

    ``git diff --name-only`` also lists files *deleted* in this push. Deletion isn't
    a supported DataHub sync operation (there is no archive/soft-delete path here —
    see .woodpecker/datahub.yml), so trying to process a deleted path would crash
    later with a bare ``FileNotFoundError`` when building the LLM prompt (mislabeled
    as "LLM call failed"). Skip those with an explicit message instead of failing the
    whole run.
    """
    candidates = [
        _REPO_ROOT / f
        for f in _git_changed_files()
        if f.startswith(_MD_PREFIXES)
        and f.endswith(".md")
        and not Path(f).name.startswith("_")
    ]
    changed: list[Path] = []
    for p in candidates:
        if not p.exists():
            print(
                f"SKIP: {p.name} was deleted in this push — DataHub publish has no "
                "delete/archive path; if the entity should be removed from DataHub, "
                "do that manually."
            )
            continue
        changed.append(p)
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
    """Full MD body minus Ownership / Tables / Synonyms / Golden Queries / DataHub-catalog sections.

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


def _as_yaml_literal_block(key: str, value: str, indent: str = "") -> str:
    """Render ``key: |`` literal block scalar with every line indented two spaces
    past ``indent`` (the key's own indentation — ``""`` for a top-level key like
    ``product_description``, ``"    "`` for a nested key like a golden query's
    ``sql:`` inside a ``golden_queries:`` list item).

    Literal blocks need no escaping (markdown ``#``, ``:``, quotes, etc. are all safe),
    so this round-trips arbitrary MD/SQL content without mangling — unlike ``yaml.dump``.
    """
    content_indent = f"{indent}  "
    indented = "\n".join(
        (f"{content_indent}{ln}" if ln else "") for ln in value.split("\n")
    )
    return f"{indent}{key}: |\n{indented}\n"


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
- Do NOT hand-author each golden query's `sql:` text — CI overwrites it with the exact
  SQL from that query's fenced ```sql block in the Markdown, injected by position after
  generation (same pattern as `product_description`). Emit a short one-line placeholder
  instead, e.g. `sql: "(injected by CI from Markdown)"`. This keeps your response small
  even for entities with many/large golden queries — you never need to reproduce SQL text.
- Glossary term `id` values must match existing DataHub term slugs when the term
  already exists; the loader resolves by display name as fallback.
- Do NOT hand-author `product_description`. CI overwrites it with the full Markdown body
  (minus ownership, MBR, asset-routing, glossary, golden-query, catalog, and upstream-entity
  sections). Emit a one-line placeholder, e.g. `product_description: "(injected by CI from Markdown)"`.
- Do NOT emit an `owners:` block — CI injects Data Owner / Data Steward emails from the
  `## Ownership` section (any hand-authored `owners:` is discarded).
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
- Do NOT emit an `mbr:` block — CI injects it from the optional `## MBR` section (the
  `**Name**` / `**Category**` pairs; any hand-authored `mbr:` is discarded).
- Do NOT emit a `catalog:` block — CI injects it from the `## Catalog` table (one
  `{{name, type}}` row per official metric; any hand-authored `catalog:` is discarded).
- Do NOT hand-author `related_data_products` — CI injects from `## Related Domain Entities`.{related_rule}"""
        )

    return (
        common
        + """
- This is a **domain entity** (`docs/llm_context/domain_entities/`). Follow the domain
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


def _call_llm(
    messages: list[dict],
    model: str,
    base_url: str,
    api_key: str,
    max_tokens: int = _DEFAULT_MAX_TOKENS,
) -> str:
    payload = {"model": model, "messages": messages, "max_tokens": max_tokens}
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

    finish_reason = choices[0].get("finish_reason")
    if finish_reason == "length":
        raise ValueError(
            "LiteLLM response was truncated (finish_reason='length') before "
            f"completing the YAML — max_tokens={max_tokens} was too low for this "
            "entity (e.g. too many/too large golden queries). Increase "
            "LITELLM_MAX_TOKENS or split the entity's Golden Queries and retry."
        )

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
        help="Process every entity MD under docs/llm_context/domain_entities/",
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
    max_tokens = int(
        os.environ.get("LITELLM_MAX_TOKENS", "").strip() or _DEFAULT_MAX_TOKENS
    )
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
            raw = _call_llm(messages, model, base_url, api_key, max_tokens=max_tokens)
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
        yaml_content = _inject_golden_query_sqls(
            yaml_content, _extract_golden_query_sqls(md_path)
        )

        expected_gq = _count_expected_golden_queries(md_path)
        actual_gq = _count_golden_queries_in_yaml(yaml_content)
        if expected_gq and actual_gq < expected_gq:
            print(
                f"   ERROR: Markdown declares {expected_gq} golden querie(s) but "
                f"the generated YAML only has {actual_gq} — LLM output is likely "
                "incomplete/truncated. Refusing to publish partial data. Re-run, "
                "or raise LITELLM_MAX_TOKENS if this entity has many/large "
                "golden queries.",
                file=sys.stderr,
            )
            failed.append(entity_slug)
            continue

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
        yaml_content = _inject_owners(yaml_content, _extract_owners(md_path))
        if _md_to_data_product_type(md_path) == "metric":
            yaml_content = _inject_metric_datasets(yaml_content, md_path)
            yaml_content = _inject_mbr(yaml_content, _extract_mbrs(md_path))

            catalog = _extract_catalog(md_path)
            unclassified = _validate_catalog_types(catalog)
            if unclassified:
                print(
                    "   ERROR: ## Catalog metric(s) missing a valid Type "
                    f"('OKR' or 'Health Metric'): {', '.join(unclassified)}. "
                    "Refusing to publish an unclassified metric catalog.",
                    file=sys.stderr,
                )
                failed.append(entity_slug)
                continue
            yaml_content = _inject_catalog(yaml_content, catalog)

            yaml_content = _inject_related_data_products(
                yaml_content, _extract_related_data_products(md_path)
            )
        else:
            yaml_content = _inject_domain_datasets(yaml_content, md_path)

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
