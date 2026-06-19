"""Parse business-entity markdown sections from DataHub Context Documents."""

from __future__ import annotations

import re
from dataclasses import dataclass, field


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
    raw_markdown: str = ""


# DataHub's rich-text editor backslash-escapes standard Markdown characters on save.
# Unescape them before any parsing so the regexes below see clean markdown.
_MD_ESCAPE_RE = re.compile(r"\\([\\`*_{}\[\]()+\-#.!|])")

_SECTION_RE = re.compile(r"^##\s+(.+)$", re.MULTILINE)
_H3_RE = re.compile(r"^###\s+(.+)$", re.MULTILINE)
# Allow unclosed code fences (DataHub editor sometimes drops the closing ```)
_SQL_BLOCK_RE = re.compile(r"```sql\s*\n(.*?)(?:```|$)", re.IGNORECASE | re.DOTALL)
_TABLE_REF_RE = re.compile(r"`([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)`")
_FROM_JOIN_RE = re.compile(
    r"(?:FROM|JOIN)\s+([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)",
    re.IGNORECASE,
)


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
    """Remove blank lines that DataHub's editor inserts between every SQL line."""
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


def parse_entity_markdown(markdown: str) -> ParsedEntityDocument:
    """Parse a TARS entity Context Document body into structured fields."""
    markdown = _MD_ESCAPE_RE.sub(r"\1", markdown)
    title = _extract_title(markdown)
    sections = _split_sections(markdown)

    overview = _find_section(sections, "overview")
    glossary_text = _find_section(sections, "glossary", "synonyms")
    tables_text = _find_section(sections, "tables", "where to query")
    golden_text = _find_section(sections, "golden")

    glossary_terms = _parse_glossary(glossary_text)
    datasets = _parse_datasets(tables_text)
    if not datasets:
        datasets = _parse_datasets(markdown)
    golden_queries = _parse_golden_queries(golden_text)

    return ParsedEntityDocument(
        title=title,
        overview=overview,
        glossary_terms=glossary_terms,
        datasets=datasets,
        golden_queries=golden_queries,
        raw_markdown=markdown,
    )


def validate_parsed_document(parsed: ParsedEntityDocument) -> list[str]:
    """Return list of validation errors (empty = valid)."""
    errors: list[str] = []
    if not parsed.title or parsed.title == "Untitled Entity":
        errors.append("Missing H1 title")
    if not parsed.overview.strip():
        errors.append("Missing ## Overview section")
    if not parsed.datasets:
        errors.append("No schema.table references found in ## Tables section")
    if not parsed.golden_queries:
        errors.append("Missing ## Golden Queries with at least one SQL block")
    return errors
