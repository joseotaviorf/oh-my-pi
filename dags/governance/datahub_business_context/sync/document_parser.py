"""Parse business-entity markdown sections from DataHub Context Documents."""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from sync.constants import DATA_PRODUCT_TYPE_DOMAIN, DATA_PRODUCT_TYPE_METRIC
from sync.markdown_sanitizer import sanitize_datahub_markdown


@dataclass
class GoldenQuery:
    name: str
    description: str
    sql: str


@dataclass
class GlossaryTerm:
    term_id: str
    name: str
    description: str


@dataclass
class ParsedEntityDocument:
    title: str
    overview: str
    glossary_terms: list[GlossaryTerm] = field(default_factory=list)
    datasets: list[tuple[str, str]] = field(default_factory=list)
    metric_dataset_rows: list[dict[str, str]] = field(default_factory=list)
    golden_queries: list[GoldenQuery] = field(default_factory=list)
    owners: dict[str, list[str]] = field(default_factory=dict)
    mbr: list[str] = field(default_factory=list)
    related_data_products: list[str] = field(default_factory=list)
    has_ownership_section: bool = False
    has_related_business_entities_section: bool = False
    raw_markdown: str = ""


# DataHub's rich-text editor backslash-escapes standard Markdown characters on save.
# Unescape them before any parsing so the regexes below see clean markdown.
_MD_ESCAPE_RE = re.compile(r"\\([\\`*_{}\[\]()+\-#.!|])")

_SECTION_RE = re.compile(r"^##\s+(.+)$", re.MULTILINE)
_H3_RE = re.compile(r"^###\s+(.+)$", re.MULTILINE)
# DataHub's rich-text editor mangles fenced SQL blocks in two ways the naive
# ```sql\n...``` pattern misses:
#   1. It stores the block inline on a single line — ```sql SELECT ... — with no
#      newline after the language tag (so requiring \s*\n drops the whole block).
#   2. It splits the closing fence with spaces (``` becomes ` ``) and sometimes
#      omits it entirely.
# Match permissively: \b after the tag avoids ```sqlite; \s* (not \s*\n) accepts
# both inline and multi-line blocks; the close is any run of backticks, optionally
# space-separated, or end-of-section for unclosed fences.
_SQL_BLOCK_RE = re.compile(
    r"```sql\b\s*(.*?)\s*(?:`(?:\s*`)+|$)",
    re.IGNORECASE | re.DOTALL,
)
_TABLE_REF_RE = re.compile(r"`([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)`")
_SUPERSET_ASSET_URN_RE = re.compile(
    r"urn:li:dataset:\(urn:li:dataPlatform:superset,[^)]+\)"
    r"|urn:li:chart:\(superset,[^)]+\)"
    r"|urn:li:dashboard:\(superset,[^)]+\)",
    re.IGNORECASE,
)
_GLOSSARY_ARROW_RE = re.compile(r"\s*(?:→|:)\s*(.+)$")
_FROM_JOIN_RE = re.compile(
    r"(?:FROM|JOIN)\s+([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)",
    re.IGNORECASE,
)

# Ownership / MBR parsing — mirrors generate_and_push_datahub_entities.py so both the
# CI path (repo .md → YAML) and the self-service sync path (DataHub document → YAML)
# produce the same spec keys. Template placeholders (wrapped in ``{...}``) never match.
_OWNER_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@quintoandar\.com(?:\.br)?$")
_OWNER_ROLE_HEADINGS = {
    "data owner": "data_owner",
    "data steward": "data_steward",
}
# 2-3 asterisks (bold, or bold+italic) with an optional redundant inner
# underscore wrap — DataHub's editor emits ``***_Data Owner:_***`` for a
# heading a human typed as plain ``**Data Owner:**``.
_OWNER_ROLE_HEADING_RE = re.compile(r"^\*{2,3}_?\s*(.+?)\s*:\s*_?\*{2,3}$")
# DataHub's editor auto-linkifies a typed email into a markdown mailto link
# (``[x@y.com](mailto:x@y.com)``) — extract the display text before validating.
_MAILTO_LINK_RE = re.compile(r"^\[([^\]]+)\]\(mailto:[^)]+\)$", re.IGNORECASE)


def _slugify(text: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "_", text.strip().lower())
    return cleaned.strip("_")


def _display_name_to_product_id(name: str) -> str:
    """``NPS`` → ``nps``; ``House and Listing`` → ``house-and-listing``."""
    return re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")


def _split_sections(markdown: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    matches = list(_SECTION_RE.finditer(markdown))
    for idx, match in enumerate(matches):
        title = match.group(1).strip()
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(markdown)
        sections[title.lower()] = markdown[start:end].strip()
    return sections


def _extract_title(markdown: str) -> str:
    for line in markdown.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return "Untitled Entity"


def _parse_glossary_bullet_line(line: str) -> GlossaryTerm | None:
    """Parse ``- **term**, **synonym** → mapping`` (metric template bullet format)."""
    stripped = line.strip()
    if not stripped.startswith("- "):
        return None
    body = stripped[2:].strip()
    arrow = _GLOSSARY_ARROW_RE.search(body)
    if not arrow:
        return None
    mapping = arrow.group(1).strip()
    left = body[: arrow.start()]
    bold_terms = [term.strip() for term in re.findall(r"\*\*([^*]+)\*\*", left)]
    if not bold_terms:
        plain = re.sub(r"\*\*", "", left).strip().strip(",").strip()
        if not plain or "{" in plain:
            return None
        bold_terms = [plain]
    primary = bold_terms[0]
    aliases = bold_terms[1:]
    display = f"{primary} ({', '.join(aliases)})" if aliases else primary
    return GlossaryTerm(
        term_id=_slugify(primary),
        name=display,
        description=mapping,
    )


def _parse_glossary(section_text: str) -> list[GlossaryTerm]:
    terms: list[GlossaryTerm] = []
    for line in section_text.splitlines():
        line = line.strip()
        if (
            not line.startswith("|")
            or line.startswith("| Term")
            or line.startswith("|---")
        ):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 2:
            continue
        name = cells[0].strip("* ")
        mapping = cells[-1] if len(cells) >= 3 else cells[1]
        term_id = _slugify(re.sub(r"\*\*", "", name).split("(")[0])
        if not term_id:
            continue
        terms.append(
            GlossaryTerm(
                term_id=term_id,
                name=re.sub(r"\*\*", "", name),
                description=mapping.strip(),
            )
        )
    if terms:
        return terms

    for line in section_text.splitlines():
        term = _parse_glossary_bullet_line(line)
        if term:
            terms.append(term)
    return terms


def _parse_datasets(section_text: str) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for schema, table in _TABLE_REF_RE.findall(section_text):
        pair = (schema, table)
        if pair not in seen:
            seen.add(pair)
            found.append(pair)
    return found


def _parse_metric_dataset_rows(section_text: str) -> list[dict[str, str]]:
    """Parse ``## Superset Golden Assets`` into Trino tables and Superset assets."""
    rows: list[dict[str, str]] = []
    seen_tables: set[tuple[str, str]] = set()
    seen_urns: set[str] = set()
    for schema, table in _TABLE_REF_RE.findall(section_text):
        key = (schema.lower(), table.lower())
        if key not in seen_tables:
            seen_tables.add(key)
            rows.append({"schema": schema, "table": table})
    for urn in _SUPERSET_ASSET_URN_RE.findall(section_text):
        urn = urn.strip()
        if urn not in seen_urns:
            seen_urns.add(urn)
            rows.append({"urn": urn})
    return rows


def _parse_related_data_products(section_text: str) -> list[str]:
    """Parse ``## Related Business Entities`` bullets into kebab-case product IDs."""
    ids: list[str] = []
    seen: set[str] = set()
    for line in section_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            raw_name = stripped[2:].strip().strip("*").strip()
        elif stripped and not stripped.startswith("#"):
            raw_name = stripped.strip("*").strip()
        else:
            continue
        product_id = _display_name_to_product_id(raw_name)
        if product_id and product_id not in seen:
            seen.add(product_id)
            ids.append(product_id)
    return ids


def _clean_sql(sql: str) -> str:
    """Normalize SQL extracted from DataHub's editor.

    Removes blank lines the editor inserts between every SQL line and trims any
    stray backtick fence remnants left over when it mangles the closing ```.
    """
    sql = sql.strip().strip("`").strip()
    lines = [ln for ln in sql.splitlines() if ln.strip()]
    return "\n".join(lines)


def _parse_golden_queries(section_text: str) -> list[GoldenQuery]:
    queries: list[GoldenQuery] = []
    h3_matches = list(_H3_RE.finditer(section_text))
    if not h3_matches:
        sql_blocks = _SQL_BLOCK_RE.findall(section_text)
        if sql_blocks:
            queries.append(
                GoldenQuery(
                    name="Query 1 — Golden query",
                    description="Canonical validated SQL for this entity.",
                    sql=_clean_sql(sql_blocks[0]),
                )
            )
        return queries

    for idx, match in enumerate(h3_matches):
        name = match.group(1).strip()
        start = match.end()
        end = (
            h3_matches[idx + 1].start()
            if idx + 1 < len(h3_matches)
            else len(section_text)
        )
        block = section_text[start:end]
        sql_match = _SQL_BLOCK_RE.search(block)
        if not sql_match:
            continue
        desc_lines = [
            ln.strip()
            for ln in block[: sql_match.start()].splitlines()
            if ln.strip() and not ln.strip().startswith(">")
        ]
        description = desc_lines[0] if desc_lines else name
        queries.append(
            GoldenQuery(
                name=name
                if name.lower().startswith("query")
                else f"Query {idx + 1} — {name}",
                description=description,
                sql=_clean_sql(sql_match.group(1)),
            )
        )
    return queries


def _parse_owners(section_text: str) -> dict[str, list[str]]:
    """Parse ``## Ownership`` into ``{"data_owner": [...], "data_steward": [...]}``.

    Reads the two bold sub-groups (``**Data Owner:**`` / ``**Data Steward:**``) and the
    ``@quintoandar.com`` / ``@quintoandar.com.br`` email bullets under each.
    Template placeholders never match.
    Each bullet may be a bare email or a DataHub auto-linkified mailto link.
    """
    owners: dict[str, list[str]] = {role: [] for role in _OWNER_ROLE_HEADINGS.values()}
    current_role: str | None = None
    for line in section_text.splitlines():
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


def _parse_mbr(section_text: str) -> list[str]:
    """Parse ``## MBR`` bullets into a de-duplicated list of MBR names (metric docs)."""
    names: list[str] = []
    seen: set[str] = set()
    for line in section_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            name = stripped[2:].strip().strip("*").strip()
        elif stripped and not stripped.startswith("#"):
            name = stripped.strip("*").strip()
        else:
            continue
        if not name or "{" in name or "}" in name:
            continue
        if name.lower() not in seen:
            seen.add(name.lower())
            names.append(name)
    return names


def _normalize_heading(text: str) -> str:
    """Strip Markdown emphasis and collapse whitespace for heading comparisons."""
    cleaned = re.sub(r"[*_`]+", "", text)
    return re.sub(r"\s+", " ", cleaned).strip().lower()


def _find_section(sections: dict[str, str], *candidates: str) -> str:
    """Return the body of the best-matching ``##`` section.

    Exact heading matches (after stripping emphasis) win over substring matches so
    a heading like ``## Pre-ownership`` cannot steal the ``ownership`` candidate
    from a later ``## Ownership`` / ``## **Ownership**`` block.
    """
    normalized_items = [
        (_normalize_heading(key), body) for key, body in sections.items()
    ]
    for candidate in candidates:
        cand = candidate.strip().lower()
        for norm_key, body in normalized_items:
            if norm_key == cand:
                return body
    for candidate in candidates:
        cand = candidate.strip().lower()
        for norm_key, body in normalized_items:
            if cand in norm_key:
                return body
    return ""


def _has_exact_section(sections: dict[str, str], heading: str) -> bool:
    """True when a ``##`` heading equals ``heading`` after emphasis stripping."""
    target = heading.strip().lower()
    return any(_normalize_heading(key) == target for key in sections)


def extract_subjects_from_sql(sql: str) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for schema, table in _FROM_JOIN_RE.findall(sql):
        pair = (schema, table)
        if pair not in seen:
            seen.add(pair)
            found.append(pair)
    return found


def parse_entity_markdown(
    markdown: str, *, fallback_title: str = ""
) -> ParsedEntityDocument:
    """Parse a TARS entity Context Document body into structured fields."""
    markdown = sanitize_datahub_markdown(markdown)
    markdown = _MD_ESCAPE_RE.sub(r"\1", markdown)
    title = _extract_title(markdown)
    _stripped_fallback = fallback_title.strip()
    if (
        title == "Untitled Entity"
        and _stripped_fallback
        and _stripped_fallback != "Untitled"
    ):
        title = _stripped_fallback
    sections = _split_sections(markdown)

    overview = _find_section(sections, "overview")
    glossary_text = _find_section(sections, "glossary", "synonyms")
    tables_text = _find_section(sections, "tables", "where to query")
    golden_text = _find_section(sections, "golden")
    ownership_text = _find_section(sections, "ownership")
    mbr_text = _find_section(sections, "mbr")
    related_text = _find_section(sections, "related business entities")
    superset_text = _find_section(sections, "superset golden")

    glossary_terms = _parse_glossary(glossary_text)
    metric_dataset_rows = _parse_metric_dataset_rows(superset_text)
    datasets = _parse_datasets(tables_text)
    if not datasets and not metric_dataset_rows:
        datasets = _parse_datasets(markdown)
    golden_queries = _parse_golden_queries(golden_text)
    owners = _parse_owners(ownership_text)
    mbr = _parse_mbr(mbr_text)
    related_data_products = _parse_related_data_products(related_text)
    # Exact heading only — substring false positives like "## Pre-ownership" must
    # not flip this flag and force Data Owner/Steward validation.
    has_ownership_section = _has_exact_section(sections, "ownership")
    has_related_business_entities_section = any(
        "related business entities" in _normalize_heading(key) for key in sections
    )

    return ParsedEntityDocument(
        title=title,
        overview=overview,
        glossary_terms=glossary_terms,
        datasets=datasets,
        metric_dataset_rows=metric_dataset_rows,
        golden_queries=golden_queries,
        owners=owners,
        mbr=mbr,
        related_data_products=related_data_products,
        has_ownership_section=has_ownership_section,
        has_related_business_entities_section=has_related_business_entities_section,
        raw_markdown=markdown,
    )


def validate_parsed_document(
    parsed: ParsedEntityDocument,
    *,
    data_product_type: str = DATA_PRODUCT_TYPE_DOMAIN,
) -> tuple[list[str], list[str]]:
    """Return blocking errors and non-blocking warnings (each list empty when none).

    Required sections differ by data product type (see the authoring templates in
    ``docs/llm_context/{business,metric}_entities/_TEMPLATE.md``):

    - Domain entities (``business_entities``) route by table and teach a canonical
      query, so they require both a ``## Tables`` / ``## Where to query what``
      section and a ``## Golden Query`` section.
    - Metric entities (``metric_entities``) are deliberately thin on schema and
      link to their business entity instead — they have no ``## Tables`` section,
      and the official ``## Calculation`` / ``## Canonical Filter`` are the source
      of truth — so neither datasets nor a golden query are required.
    """
    is_metric = data_product_type == DATA_PRODUCT_TYPE_METRIC
    errors: list[str] = []
    warnings: list[str] = []
    if not parsed.title or parsed.title == "Untitled Entity":
        errors.append("Missing H1 title")
    if not parsed.overview.strip():
        errors.append("Missing ## Overview section")
    if not is_metric and not parsed.datasets:
        errors.append("No schema.table references found in ## Tables section")
    if not is_metric and not parsed.golden_queries:
        errors.append("Missing ## Golden Queries with at least one SQL block")
    if is_metric and parsed.has_ownership_section:
        if not parsed.owners.get("data_owner"):
            errors.append("Missing Data Owner email in ## Ownership section")
        if not parsed.owners.get("data_steward"):
            errors.append("Missing Data Steward email in ## Ownership section")
    if (
        is_metric
        and parsed.has_related_business_entities_section
        and not parsed.related_data_products
    ):
        warnings.append(
            "## Related Business Entities section is present but no entities were parsed"
        )
    return errors, warnings
