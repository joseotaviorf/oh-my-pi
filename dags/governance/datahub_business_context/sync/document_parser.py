"""Parse business-entity markdown sections from DataHub Context Documents."""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from sync.constants import DATA_PRODUCT_TYPE_DOMAIN, DATA_PRODUCT_TYPE_METRIC


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
    golden_queries: list[GoldenQuery] = field(default_factory=list)
    owners: dict[str, list[str]] = field(default_factory=dict)
    mbr: list[str] = field(default_factory=list)
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
_FROM_JOIN_RE = re.compile(
    r"(?:FROM|JOIN)\s+([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)",
    re.IGNORECASE,
)

# Ownership / MBR parsing — mirrors generate_and_push_datahub_entities.py so both the
# CI path (repo .md → YAML) and the self-service sync path (DataHub document → YAML)
# produce the same spec keys. Template placeholders (wrapped in ``{...}``) never match.
_OWNER_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@quintoandar\.com\.br$")
_OWNER_ROLE_HEADINGS = {
    "data owner": "data_owner",
    "data steward": "data_steward",
}
_OWNER_ROLE_HEADING_RE = re.compile(r"^\*\*\s*(.+?)\s*:\s*\*\*$")


def _slugify(text: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "_", text.strip().lower())
    return cleaned.strip("_")


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
        line = line.strip()
        if not line.startswith("- **"):
            continue
        match = re.match(r"- \*\*(.+?)\*\*(?:\s*\((.+?)\))?\s*(?:→|:)\s*(.+)", line)
        if not match:
            continue
        name = match.group(1).strip()
        aliases = match.group(2) or ""
        mapping = match.group(3).strip()
        display = f"{name} ({aliases})" if aliases else name
        terms.append(
            GlossaryTerm(
                term_id=_slugify(name),
                name=display,
                description=mapping,
            )
        )
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
    ``@quintoandar.com.br`` email bullets under each. Template placeholders never match.
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
        if _OWNER_EMAIL_RE.match(email) and email not in owners[current_role]:
            owners[current_role].append(email)
    return owners


def _parse_mbr(section_text: str) -> list[str]:
    """Parse ``## MBR`` bullets into a de-duplicated list of MBR names (metric docs)."""
    names: list[str] = []
    seen: set[str] = set()
    for line in section_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        name = stripped[2:].strip().strip("*").strip()
        if not name or "{" in name or "}" in name:
            continue
        if name.lower() not in seen:
            seen.add(name.lower())
            names.append(name)
    return names


def _find_section(sections: dict[str, str], *candidates: str) -> str:
    for key, body in sections.items():
        for candidate in candidates:
            if candidate in key:
                return body
    return ""


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
    mbr_text = sections.get("mbr", "")

    glossary_terms = _parse_glossary(glossary_text)
    datasets = _parse_datasets(tables_text)
    if not datasets:
        datasets = _parse_datasets(markdown)
    golden_queries = _parse_golden_queries(golden_text)
    owners = _parse_owners(ownership_text)
    mbr = _parse_mbr(mbr_text)

    return ParsedEntityDocument(
        title=title,
        overview=overview,
        glossary_terms=glossary_terms,
        datasets=datasets,
        golden_queries=golden_queries,
        owners=owners,
        mbr=mbr,
        raw_markdown=markdown,
    )


def validate_parsed_document(
    parsed: ParsedEntityDocument,
    *,
    data_product_type: str = DATA_PRODUCT_TYPE_DOMAIN,
) -> list[str]:
    """Return list of validation errors (empty = valid).

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
    if not parsed.title or parsed.title == "Untitled Entity":
        errors.append("Missing H1 title")
    if not parsed.overview.strip():
        errors.append("Missing ## Overview section")
    if not is_metric and not parsed.datasets:
        errors.append("No schema.table references found in ## Tables section")
    if not is_metric and not parsed.golden_queries:
        errors.append("Missing ## Golden Queries with at least one SQL block")
    return errors
