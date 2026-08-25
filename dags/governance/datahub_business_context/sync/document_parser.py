"""Parse business-entity markdown sections from DataHub Context Documents."""

from __future__ import annotations

import re
from collections.abc import Callable
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
    mbr: list[dict[str, str]] = field(default_factory=list)
    catalog: list[dict[str, str]] = field(default_factory=list)
    related_data_products: list[str] = field(default_factory=list)
    has_ownership_section: bool = False
    has_related_domain_entities_section: bool = False
    raw_markdown: str = ""


# DataHub's rich-text editor backslash-escapes standard Markdown characters on save.
# Unescape them before any parsing so the regexes below see clean markdown. ``|`` is
# deliberately NOT in this set: inside a table it is the cell delimiter, so unescaping
# it here would split a metric name that legitimately contains one (``EC|ES2CS``) into
# two cells. The table parsers unescape it per cell instead (``_split_table_row``).
_MD_ESCAPE_RE = re.compile(r"\\([\\`*_{}\[\]()+\-#.!])")

_SECTION_RE = re.compile(r"^##\s+(.+)$", re.MULTILINE)
_H3_RE = re.compile(r"^###\s+(.+)$", re.MULTILINE)
_HEADING_RE = re.compile(r"^(#{2,3})\s+(.+)$", re.MULTILINE)
_GOLDEN_QUERY_INDIVIDUAL_HEADING_RE = re.compile(
    r"^golden quer(?:y|ies)\b(?:\s|$|[—:\-–(])",
    re.IGNORECASE,
)
_GOLDEN_QUERY_EXCLUDE_HEADING_RE = re.compile(
    r"superset\s+golden|golden\s+assets?",
    re.IGNORECASE,
)
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
# ``**Name** Post Contract`` / ``**Category:** Quality`` — the colon may sit inside or
# outside the bold wrap, or be absent entirely (the authoring template omits it).
_MBR_FIELD_RE = re.compile(
    r"^\*{2,3}_?\s*(name|category)\s*:?\s*_?\*{2,3}\s*:?\s*(.*)$", re.IGNORECASE
)
# ``## Catalog`` Type column — canonical spelling per lowercased alias, so a value
# authored in any case lands on one filterable structured-property value.
_CATALOG_TYPE_OKR = "OKR"
_CATALOG_TYPE_HEALTH = "Health Metric"
_CATALOG_TYPE_ALIASES = {
    "okr": _CATALOG_TYPE_OKR,
    "okrs": _CATALOG_TYPE_OKR,
    "health metric": _CATALOG_TYPE_HEALTH,
    "health metrics": _CATALOG_TYPE_HEALTH,
    "health-metric": _CATALOG_TYPE_HEALTH,
    "health_metric": _CATALOG_TYPE_HEALTH,
    "health": _CATALOG_TYPE_HEALTH,
}
_CATALOG_VALID_TYPES = frozenset({_CATALOG_TYPE_OKR, _CATALOG_TYPE_HEALTH})
_CATALOG_HEADER_NAMES = frozenset({"metric", "metrics", "metric name"})

# Optional metric sections — omit entirely when N/A; an empty heading is invalid.
_METRIC_OPTIONAL_SECTIONS = (
    "mbr",
    "targets and okrs",
    "superset golden assets",
)
# Optional domain sections — omit entirely when N/A; an empty heading is invalid.
_DOMAIN_OPTIONAL_SECTIONS = ("related metric entities",)
_HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def _slugify(text: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "_", text.strip().lower())
    return cleaned.strip("_")


def _display_name_to_product_id(name: str) -> str:
    """``NPS`` → ``nps``; ``House and Listing`` → ``house-and-listing``."""
    return re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")


def _split_table_row(line: str) -> list[str]:
    """Split a Markdown table row into cells, honouring escaped pipes.

    A metric name may legitimately contain a pipe (``EC|ES2CS``), which Markdown
    requires the author to escape as ``EC\\|ES2CS``. Splitting naively on ``|`` would
    tear that name in half and shift every following cell.
    """
    cells = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [cell.replace(r"\|", "|").strip() for cell in cells]


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
        cells = _split_table_row(line)
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
    """Parse ``## Related Domain Entities`` bullets into kebab-case product IDs."""
    ids: list[str] = []
    seen: set[str] = set()
    # Template leftovers such as ``<!-- optional -->`` must not become product IDs
    # (``optional``); strip HTML comments before treating leftover lines as names.
    cleaned = _HTML_COMMENT_RE.sub("", section_text or "")
    for line in cleaned.splitlines():
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


def _is_individual_golden_query_heading(heading: str) -> bool:
    norm = _normalize_heading(heading)
    if _GOLDEN_QUERY_EXCLUDE_HEADING_RE.search(norm):
        return False
    if norm in ("golden queries", "golden query"):
        return False
    return bool(_GOLDEN_QUERY_INDIVIDUAL_HEADING_RE.match(norm))


def _collect_individual_golden_query_sections(
    markdown: str,
) -> list[tuple[str, str]]:
    """Fallback for docs with several standalone ``## Golden query: {Name}`` H2s
    instead of one ``## Golden Queries`` section (``_find_section`` only returns
    the first matching heading's body, so a second/third such H2 is otherwise
    dropped).

    Restricted to H2 (``level == 2``) to stay in lockstep with the authoritative
    publisher (``generate_and_push_datahub_entities.py``'s ``_GOLDEN_QUERY_SINGULAR_
    HEADING_RE`` / ``_GOLDEN_QUERY_SECTION_HEADING_RE``), which only ever opens a
    golden-query zone on an H2 — never on an H3 nested under an unrelated parent
    heading (e.g. an arbitrary ``## For Rent (RENT)`` segment container). Matching
    H3s here would let a doc pass this parser's validation while the publisher
    extracts zero golden queries from the same file — see the regression test
    ``test_h3_under_unrelated_h2_is_not_a_golden_query``.
    """
    matches = list(_HEADING_RE.finditer(markdown))
    sections: list[tuple[str, str]] = []
    for idx, match in enumerate(matches):
        level = len(match.group(1))
        if level != 2:
            continue
        title = match.group(2).strip()
        if not _is_individual_golden_query_heading(title):
            continue
        start = match.end()
        end = len(markdown)
        for nxt in matches[idx + 1 :]:
            if len(nxt.group(1)) <= level:
                end = nxt.start()
                break
        sections.append((title, markdown[start:end]))
    return sections


def _golden_query_from_block(
    name: str,
    block: str,
    *,
    idx: int,
) -> GoldenQuery | None:
    sql_match = _SQL_BLOCK_RE.search(block)
    if not sql_match:
        return None
    desc_lines = [
        ln.strip()
        for ln in block[: sql_match.start()].splitlines()
        if ln.strip() and not ln.strip().startswith(">")
    ]
    description = desc_lines[0] if desc_lines else name
    display_name = (
        name if name.lower().startswith("query") else f"Query {idx + 1} — {name}"
    )
    return GoldenQuery(
        name=display_name,
        description=description,
        sql=_clean_sql(sql_match.group(1)),
    )


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
        parsed = _golden_query_from_block(name, block, idx=idx)
        if parsed:
            queries.append(parsed)
    return queries


def _parse_golden_queries_from_markdown(markdown: str) -> list[GoldenQuery]:
    queries: list[GoldenQuery] = []
    for idx, (name, block) in enumerate(
        _collect_individual_golden_query_sections(markdown)
    ):
        parsed = _golden_query_from_block(name, block, idx=idx)
        if parsed:
            queries.append(parsed)
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


def _is_placeholder(value: str) -> bool:
    """True for an unfilled authoring placeholder such as ``{MBR Name}`` or ``{category}``."""
    return not value or "{" in value or "}" in value


def _parse_mbr(section_text: str) -> list[dict[str, str]]:
    """Parse ``## MBR`` into a de-duplicated list of ``{name, category}`` (metric docs).

    Reads the ``**Name** {MBR name}`` / ``**Category** {category}`` pairs, repeated once
    per MBR when the document feeds several. The legacy ``- {MBR name}`` bullet form is
    still accepted (category omitted) so a document that has not been migrated yet keeps
    publishing its MBR membership.
    """
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
    for line in section_text.splitlines():
        stripped = line.strip()
        field_match = _MBR_FIELD_RE.match(stripped)
        if field_match:
            key, value = field_match.group(1).lower(), field_match.group(2).strip()
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
        elif stripped and not stripped.startswith("#") and not stripped.startswith("*"):
            _add(stripped.strip("*").strip())
    if pending_name is not None:
        _add(pending_name)
    return entries


def _normalize_catalog_type(raw: str) -> str:
    """Map an authored Type cell onto its canonical spelling (``OKR``/``Health Metric``).

    Unknown values are kept verbatim rather than dropped: the row still reaches DataHub,
    where a reviewer can see and correct it, instead of silently disappearing.
    """
    cleaned = re.sub(r"[*`]+", "", raw).strip()
    return _CATALOG_TYPE_ALIASES.get(cleaned.lower(), cleaned)


def _parse_catalog(section_text: str) -> list[dict[str, str]]:
    """Parse the ``## Catalog`` ``| Metric | Type |`` table into ``{name, type}`` rows."""
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    for line in section_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = _split_table_row(stripped)
        if len(cells) < 2 or set(cells[0]) <= {"-", ":", " "}:
            continue
        name = re.sub(r"[*`]+", "", cells[0]).strip()
        name_key = name.lower()
        type_key = re.sub(r"[*`]+", "", cells[1]).strip().lower()
        if name_key in _CATALOG_HEADER_NAMES or type_key == "type":
            continue
        if _is_placeholder(name):
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


def _normalize_heading(text: str) -> str:
    """Strip Markdown emphasis and collapse whitespace for heading comparisons."""
    cleaned = re.sub(r"[*_`]+", "", text)
    return re.sub(r"\s+", " ", cleaned).strip().lower()


def _find_section(
    sections: dict[str, str], *candidates: str, exact_only: bool = False
) -> str:
    """Return the body of the best-matching ``##`` section.

    Exact heading matches (after stripping emphasis) win over substring matches so
    a heading like ``## Pre-ownership`` cannot steal the ``ownership`` candidate
    from a later ``## Ownership`` / ``## **Ownership**`` block. ``exact_only`` disables
    the substring fallback entirely — required for ``catalog``, where the unrelated
    ``## DataHub Catalog`` section would otherwise match.
    """
    normalized_items = [
        (_normalize_heading(key), body) for key, body in sections.items()
    ]
    for candidate in candidates:
        cand = candidate.strip().lower()
        for norm_key, body in normalized_items:
            if norm_key == cand:
                return body
    if exact_only:
        return ""
    for candidate in candidates:
        cand = candidate.strip().lower()
        for norm_key, body in normalized_items:
            if cand in norm_key:
                return body
    return ""


# A Dos and Don'ts line leading with "Do" / "Don't", in either common authoring
# style: a bold label (``**Do:**`` / ``**Don't:**``) or a bullet (``- Do …``).
# ``do\b`` can't match the ``do`` inside ``don't`` (the ``n`` blocks the boundary).
_DO_LINE_RE = re.compile(r"(?im)^\s*(?:[-*]\s*)?\*{0,2}do\b")
_DONT_LINE_RE = re.compile(r"(?im)^\s*(?:[-*]\s*)?\*{0,2}don'?t\b")


def _has_do_and_dont(section_body: str) -> bool:
    """Heuristic: the Dos and Don'ts body names at least one Do AND one Don't.

    Advisory only (drives a warning, never a blocking error), so it accepts either
    authoring style — a bold label or a bullet — rather than requiring a fixed shape.
    """
    return bool(_DONT_LINE_RE.search(section_body) and _DO_LINE_RE.search(section_body))


def _has_exact_section(sections: dict[str, str], heading: str) -> bool:
    """True when a ``##`` heading equals ``heading`` after emphasis stripping."""
    target = heading.strip().lower()
    return any(_normalize_heading(key) == target for key in sections)


def _has_h3_subsection(section_body: str, *candidates: str) -> bool:
    """True when an ``###`` subsection matches one of ``candidates`` with content."""
    targets = {c.strip().lower() for c in candidates}
    body = section_body or ""
    h3_matches = list(_H3_RE.finditer(body))
    for idx, match in enumerate(h3_matches):
        if _normalize_heading(match.group(1)) not in targets:
            continue
        start = match.end()
        end = h3_matches[idx + 1].start() if idx + 1 < len(h3_matches) else len(body)
        if _section_has_content(body[start:end]):
            return True
    return False


def _relationships_section(sections: dict[str, str]) -> str:
    """Return the body of ``## Relationships …`` (flexible heading match)."""
    for key, body in sections.items():
        norm = _normalize_heading(key)
        if norm == "relationships" or norm.startswith("relationships with"):
            return body
    return ""


def _validate_catalog_rows(catalog: list[dict[str, str]]) -> list[str]:
    """Blocking errors for ``## Catalog`` rows missing or with invalid Type."""
    errors: list[str] = []
    if not catalog:
        errors.append(
            "Missing ## Catalog section with at least one metric row "
            "(Type must be OKR or Health Metric)"
        )
        return errors
    invalid = [
        row["name"] for row in catalog if row.get("type") not in _CATALOG_VALID_TYPES
    ]
    if invalid:
        errors.append(
            "## Catalog metric(s) missing a valid Type ('OKR' or 'Health Metric'): "
            + ", ".join(invalid)
        )
    return errors


def _section_has_content(body: str) -> bool:
    """True when section body has content beyond template HTML comments."""
    return bool(_HTML_COMMENT_RE.sub("", body or "").strip())


def _optional_section_has_content(body: str) -> bool:
    return _section_has_content(body)


def _validate_optional_sections_not_empty(
    sections: dict[str, str],
    *,
    optional_headings: tuple[str, ...],
) -> list[str]:
    """Error when an optional ``##`` heading exists but its body is empty."""
    optional_norm = {heading.strip().lower() for heading in optional_headings}
    errors: list[str] = []
    for key, body in sections.items():
        if _normalize_heading(key) in optional_norm and not _section_has_content(body):
            errors.append(
                f"Optional section ## {key.strip()} is present but empty — "
                "omit the heading entirely when it does not apply"
            )
    return errors


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
    markdown: str,
    *,
    fallback_title: str = "",
    unescape: bool = True,
    sanitize_fn: Callable[[str], str] = sanitize_datahub_markdown,
) -> ParsedEntityDocument:
    """Parse a TARS entity Context Document body into structured fields.

    ``unescape`` and ``sanitize_fn`` let the same parser serve a non-DataHub source
    (a hand-uploaded ``.md``) without corrupting the author's formatting: a Luigi
    caller passes ``unescape=False`` (hand-authored markdown isn't backslash-escaped)
    and the lighter :func:`sync.markdown_sanitizer.sanitize_uploaded_markdown` (so the
    aggressive DataHub-export rewrites don't touch intentional formatting). The
    defaults reproduce today's DataHub behavior exactly.
    """
    # Unescape BEFORE sanitizing: DataHub backslash-escapes markdown special
    # chars (see _MD_ESCAPE_RE below), and the sanitizer's emphasis/heading
    # regexes only match literal `*`/`_` runs. Sanitizing first left escaped
    # artifacts (e.g. ``**\_Data Owner:\_**``) untouched, since the escaping
    # backslash breaks the regex; unescaping afterward then revealed the
    # un-sanitized ``**_Data Owner:_**`` in the final output.
    if unescape:
        markdown = _MD_ESCAPE_RE.sub(r"\1", markdown)
    markdown = sanitize_fn(markdown)
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
    golden_text = _find_section(
        sections, "golden queries", "golden query", exact_only=True
    )
    ownership_text = _find_section(sections, "ownership")
    mbr_text = _find_section(sections, "mbr")
    catalog_text = _find_section(sections, "catalog", exact_only=True)
    related_text = _find_section(sections, "related domain entities")
    superset_text = _find_section(sections, "superset golden assets", exact_only=True)

    glossary_terms = _parse_glossary(glossary_text)
    metric_dataset_rows = _parse_metric_dataset_rows(superset_text)
    datasets = _parse_datasets(tables_text)
    if not datasets and not metric_dataset_rows:
        datasets = _parse_datasets(markdown)
    golden_queries = _parse_golden_queries(golden_text)
    if not golden_queries:
        golden_queries = _parse_golden_queries_from_markdown(markdown)
    owners = _parse_owners(ownership_text)
    mbr = _parse_mbr(mbr_text)
    catalog = _parse_catalog(catalog_text)
    related_data_products = _parse_related_data_products(related_text)
    # Exact heading only — substring false positives like "## Pre-ownership" must
    # not flip this flag and force Data Owner/Steward validation.
    has_ownership_section = _has_exact_section(sections, "ownership")
    has_related_domain_entities_section = any(
        "related domain entities" in _normalize_heading(key) for key in sections
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
        catalog=catalog,
        related_data_products=related_data_products,
        has_ownership_section=has_ownership_section,
        has_related_domain_entities_section=has_related_domain_entities_section,
        raw_markdown=markdown,
    )


def validate_parsed_document(
    parsed: ParsedEntityDocument,
    *,
    data_product_type: str = DATA_PRODUCT_TYPE_DOMAIN,
) -> tuple[list[str], list[str]]:
    """Return blocking errors and non-blocking warnings (each list empty when none).

    The single authoritative gate for the template contract: the enforced required
    set is kept equal to the set documented in the authoring templates and
    ``create-{metric,business}-entity-doc`` skills, so a doc the skill (or the Luigi
    bot) tells an author to produce is exactly the doc this gate accepts.

    Both types share the same core: H1, ``## Overview``, ``## Ownership`` (Data Owner
    AND Data Steward), ``## Glossary and Synonyms``, ``## Dos and Don'ts`` and
    ``## Golden Queries``. Only the type-specific sections differ — domain adds
    ``## Tables`` (concrete ``schema.table``); metric adds ``## Related Domain
    Entities``, ``## Scope`` and ``## Calculation``.

    Legacy docs missing a newly-required section aren't retroactively broken: the CI
    gate runs ``--changed-only`` and TARS sync skips an incomplete doc rather than
    failing it.
    """
    is_metric = data_product_type == DATA_PRODUCT_TYPE_METRIC
    errors: list[str] = []
    warnings: list[str] = []
    sections = _split_sections(parsed.raw_markdown or "")

    # Required for BOTH entity types (kept in lockstep with Zordon's dp_validator):
    # title, Overview, an Ownership section naming a Data Owner AND a Data Steward
    # @quintoandar email, a Glossary, a Dos and Don'ts, and at least one Golden Query.
    if not parsed.title or parsed.title == "Untitled Entity":
        errors.append("Missing H1 title")
    if not _section_has_content(parsed.overview):
        errors.append("Missing ## Overview section")
    if not parsed.has_ownership_section:
        errors.append("Missing ## Ownership section")
    else:
        if not parsed.owners.get("data_owner"):
            errors.append("Missing Data Owner email in ## Ownership section")
        if not parsed.owners.get("data_steward"):
            errors.append("Missing Data Steward email in ## Ownership section")
    glossary = _find_section(sections, "glossary and synonyms", "glossary", "synonyms")
    if not _section_has_content(glossary):
        errors.append("Missing ## Glossary and Synonyms section")
    dos_and_donts = _find_section(
        sections, "dos and don'ts", "dos and don", "do's and don"
    )
    if not _section_has_content(dos_and_donts):
        errors.append("Missing ## Dos and Don'ts section")
    elif not _has_do_and_dont(dos_and_donts):
        # Advisory (non-blocking): the section is present and non-empty, but the
        # authoring guidance asks for at least one Do AND one Don't. Left to the
        # reviewer rather than blocked, so CI never diverges from Zordon's gate.
        warnings.append("## Dos and Don'ts should list at least one Do and one Don't")
    if not parsed.golden_queries:
        errors.append("Missing ## Golden Queries with at least one SQL block")

    errors.extend(
        _validate_optional_sections_not_empty(
            sections, optional_headings=_DOMAIN_OPTIONAL_SECTIONS
        )
    )

    if not is_metric:
        # Domain-specific: routes by table, so it needs concrete schema.table refs.
        if not parsed.datasets:
            errors.append("No schema.table references found in ## Tables section")
        key_metrics = _find_section(sections, "key metrics")
        if not _section_has_content(key_metrics):
            errors.append("Missing ## Key Metrics section")
        relationships = _relationships_section(sections)
        if not _section_has_content(relationships):
            errors.append("Missing ## Relationships with other entities section")
        return errors, warnings

    # Metric-specific: links to a domain entity and defines the calculation.
    errors.extend(_validate_catalog_rows(parsed.catalog))
    errors.extend(
        _validate_optional_sections_not_empty(
            sections, optional_headings=_METRIC_OPTIONAL_SECTIONS
        )
    )
    if not parsed.has_related_domain_entities_section:
        errors.append("Missing ## Related Domain Entities section")
    elif not parsed.related_data_products:
        errors.append(
            "## Related Domain Entities section is present but no entities were parsed"
        )
    scope = _find_section(sections, "scope")
    if not _section_has_content(scope):
        errors.append("Missing ## Scope section")
    elif not ("included" in scope.lower() and "excluded" in scope.lower()):
        warnings.append(
            "## Scope should list both what is Included and what is Excluded"
        )
    calculation = _find_section(sections, "calculation")
    if not _section_has_content(calculation):
        errors.append("Missing ## Calculation section")
    else:
        if not _has_h3_subsection(calculation, "canonical filter"):
            errors.append(
                "## Calculation must include a ### Canonical Filter subsection"
            )
        if not _has_h3_subsection(calculation, "nuances"):
            errors.append("## Calculation must include a ### Nuances subsection")
    return errors, warnings
