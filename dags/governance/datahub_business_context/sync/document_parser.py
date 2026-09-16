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
class ParsedMetric:
    """One ``### {Metric Name}`` block inside the ``## Metrics`` section.

    ``headings`` holds every ``####`` heading actually present (so a present-but-empty
    optional heading can be rejected) and ``duplicate_headings`` the ones authored more
    than once — the later body wins, which is worth a warning rather than a silent
    overwrite.
    """

    name: str
    slug: str = ""
    description: str = ""
    also_known_as: str = ""
    rules: str = ""
    metric_type: str = ""
    direction: str = ""
    grain: str = ""
    is_additive: str = ""
    business_stage: str = ""
    acronym: str = ""
    mbr: str = ""
    category: str = ""
    golden_query: GoldenQuery | None = None
    glossary_terms: list[GlossaryTerm] = field(default_factory=list)
    headings: set[str] = field(default_factory=set)
    duplicate_headings: list[str] = field(default_factory=list)


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
    metrics: list[ParsedMetric] = field(default_factory=list)
    domain: str = ""
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
_H4_RE = re.compile(r"^####\s+(.+)$", re.MULTILINE)
_HEADING_RE = re.compile(r"^(#{2,3})\s+(.+)$", re.MULTILINE)
# A single metric doc may hold a family of related metrics, but not without bound —
# past ~10 the document stops being a coherent contract and should be split.
_MAX_METRICS_PER_DOCUMENT = 10
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

# Per-metric closed vocabularies. Each maps a lowercased authored spelling onto the one
# canonical value, so a field authored in any reasonable case/phrasing lands on a single
# filterable value downstream (structured property today, metric metadata YAML in the
# generator phase). Anything outside the map is a blocking error, not a passthrough:
# unlike ``## Catalog``'s Type — where an unknown value still reached a human reviewer in
# DataHub — these feed generated files nobody re-reads.
_METRIC_DIRECTION_ALIASES = {
    "higher is better": "Higher is better",
    "lower is better": "Lower is better",
    "neutral": "Neutral",
}
_METRIC_GRAIN_ALIASES = {
    "daily": "daily",
    "weekly": "weekly",
    "monthly": "monthly",
    "quarterly": "quarterly",
    "yearly": "yearly",
    "annual": "yearly",
}
# Mirrors the ``business_stage`` values already in use across dags/**/metadata/metric/.
_METRIC_BUSINESS_STAGES = {
    "platform operations": "Platform Operations",
    "demand": "Demand",
    "supply": "Supply",
    "collections": "Collections",
    "offboarding": "Offboarding",
    "cx": "CX",
    "post contract": "Post Contract",
    "other": "Other",
}
_METRIC_BOOLEAN_ALIASES = {
    "true": "true",
    "yes": "true",
    "false": "false",
    "no": "false",
}
# The slug is the stable key between this document and the metric table the generator
# phase will materialize from it, so it has to survive a display-name rename: snake_case,
# frozen at creation.
_METRIC_SLUG_RE = re.compile(r"^[a-z][a-z0-9_]*$")

# Required ``####`` headings inside a ``### {Metric Name}`` block, mapped to the
# ``ParsedMetric`` attribute each one fills.
_METRIC_REQUIRED_H4 = (
    ("slug", "Slug"),
    ("description", "Description"),
    ("also_known_as", "Also Known As"),
    ("rules", "Rules"),
    ("metric_type", "Type"),
    ("direction", "Direction"),
    ("grain", "Grain"),
    ("is_additive", "Is Additive"),
)

# Of those, the multi-line prose ones. ``_is_placeholder`` is a contains-a-brace
# test written for scalar values like ``{MBR Name}``; in prose a brace is ordinary
# content (a ``{start_date}`` parameter, JSON, set notation), so applying it here
# would reject filled sections with a misleading "missing heading" error. A section
# left as an actual stub is still caught by the file-level placeholder scan in
# ``validate_datahub_context_entities``, which strips code fences first.
_METRIC_PROSE_H4 = frozenset({"description", "rules", "also_known_as"})

# Optional metric sections — omit entirely when N/A; an empty heading is invalid.
# Per-metric ``#### MBR`` / ``#### Category`` are validated inside ``## Metrics``
# (see ``_validate_metrics``), not here — this tuple lists only top-level ``##`` sections.
_METRIC_OPTIONAL_SECTIONS = (
    "related domain entities",
    "targets and okrs",
)
# Per-metric optional H4 headings — present-but-empty is invalid, same rule as the
# top-level optional sections above.
#
# ``acronym`` and ``business_stage`` are a step beyond optional: no template offers them
# and no authoring flow emits them. They are tolerated so that a document already
# carrying one keeps parsing, and so the eventual migration of the legacy corpus is a
# deletion rather than a rejection. Both map to metric-layer columns that are optional
# there too, and that the generator phase leaves blank on purpose.
#
# ``acronym`` — across the 696 metrics in ``dags/**/metadata/metric/`` the field is
# ~100% filled, but 43% of the values are the metric name repeated ("Amount Contacts")
# or a machine-built initialism nobody says out loud ("TWDATWOR"): the signature of a
# mandatory field with no natural value. An abbreviation the business really uses is an
# alias, so it goes in ``#### Also Known As``, which takes as many as the metric has
# instead of forcing exactly one — and which is the list published as glossary terms.
#
# ``business_stage`` — well filled and classified with care, but with no reader. 6 of
# the 7 domains map to exactly one stage: for 464 of the ~700 metrics the domain already
# determines the answer, and values like ``Conversational XP`` are the domain name
# restated. Only For Rent, with a long asset lifecycle, uses it as a real axis. Nothing
# consumes it downstream either — it sits in ``optional_args`` of
# ``upload_metadata_files_into_s3.py``, and no Superset dataset, chart, saved query or
# SQL Lab query references the column. A present value is still vocabulary-checked.
_METRIC_OPTIONAL_H4 = ("mbr", "category", "acronym", "business_stage")
# Heading as authored, for error messages — the parsed key is lowercased.
_METRIC_OPTIONAL_H4_LABELS = {
    "mbr": "MBR",
    "category": "Category",
    "acronym": "Acronym",
    "business_stage": "Business Stage",
}
# Optional sections of the *pre-redesign* metric template, still enforced for documents
# that have not been migrated yet (see ``_validate_legacy_metric_document``).
_LEGACY_METRIC_OPTIONAL_SECTIONS = (
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


def _parse_metric_glossary(
    section_text: str, *, metric_name: str
) -> list[GlossaryTerm]:
    """Parse a per-metric ``#### Also Known As`` bullet list into glossary terms.

    The entity-level ``## Glossary and Synonyms`` needs an explicit ``→ {Metric Name}``
    on every bullet, because one flat list serves every metric in the document — which
    is also how an alias set silently ends up covering only the first metric. Nested
    under ``### {Metric Name}`` the owner is structural, so a bare ``- **term**`` is
    enough and the arrow is reserved for the case that still needs one: a **near-miss**,
    a name that sounds like this metric but means something else, where the text after
    the arrow is the correction rather than the owner.

    Terms are flattened into the document-level list by :func:`parse_entity_markdown`,
    so the published payload is identical either way.
    """
    terms: list[GlossaryTerm] = []
    for line in (section_text or "").splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        term = _parse_glossary_bullet_line(stripped)
        if term is None:
            # No arrow: an alias of the metric it is nested under.
            body = stripped[2:].strip()
            bold = [found.strip() for found in re.findall(r"\*\*([^*]+)\*\*", body)]
            if not bold:
                plain = body.strip().strip(",").strip()
                if not plain or "{" in plain:
                    continue
                bold = [plain]
            primary, aliases = bold[0], bold[1:]
            term = GlossaryTerm(
                term_id=_slugify(primary),
                name=f"{primary} ({', '.join(aliases)})" if aliases else primary,
                description=metric_name,
            )
        if term.term_id:
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


def _split_h4_sections(block: str) -> tuple[dict[str, str], list[str]]:
    """Split a ``### {Metric Name}`` block into its ``#### `` subsections.

    Returns ``({normalized_heading: body}, duplicate_headings)``. A heading is present as
    a key even when its body is empty, so a present-but-empty optional heading
    (``#### MBR`` with nothing under it) can be detected and rejected. When the same
    heading is authored twice the last body wins and the heading is reported as a
    duplicate — overwriting one silently is how a corrected value ends up ignored.
    """
    out: dict[str, str] = {}
    duplicates: list[str] = []
    matches = list(_H4_RE.finditer(block))
    for idx, match in enumerate(matches):
        title = _normalize_heading(match.group(1))
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(block)
        if title in out and title not in duplicates:
            duplicates.append(title)
        out[title] = block[start:end].strip()
    return out, duplicates


def _scalar_field(body: str) -> str:
    """First meaningful line of a single-value ``####`` body, stripped of emphasis.

    The authoring template puts an HTML guidance comment under most headings, so the
    value is rarely the literal first line.
    """
    cleaned = _HTML_COMMENT_RE.sub("", body or "")
    for line in cleaned.splitlines():
        stripped = re.sub(r"[*`]+", "", line).strip().rstrip(".")
        if stripped:
            return stripped
    return ""


def _parse_metrics(section_text: str) -> list[ParsedMetric]:
    """Parse the ``## Metrics`` section into one :class:`ParsedMetric` per ``###`` block."""
    metrics: list[ParsedMetric] = []
    h3_matches = list(_H3_RE.finditer(section_text or ""))
    for idx, match in enumerate(h3_matches):
        name = re.sub(r"[*`]+", "", match.group(1)).strip()
        start = match.end()
        end = (
            h3_matches[idx + 1].start()
            if idx + 1 < len(h3_matches)
            else len(section_text)
        )
        block = section_text[start:end]
        subs, duplicates = _split_h4_sections(block)
        gq_body = subs.get("golden query") or subs.get("golden queries") or ""
        golden = _golden_query_from_block(name, gq_body, idx=idx) if gq_body else None
        aka = subs.get("also known as", "")
        metrics.append(
            ParsedMetric(
                name=name,
                slug=_scalar_field(subs.get("slug", "")),
                description=subs.get("description", ""),
                also_known_as=aka,
                rules=subs.get("rules", ""),
                metric_type=_scalar_field(subs.get("type", "")),
                direction=_scalar_field(subs.get("direction", "")),
                grain=_scalar_field(subs.get("grain", "")),
                is_additive=_scalar_field(subs.get("is additive", "")),
                business_stage=_scalar_field(subs.get("business stage", "")),
                acronym=_scalar_field(subs.get("acronym", "")),
                mbr=subs.get("mbr", ""),
                category=subs.get("category", ""),
                golden_query=golden,
                glossary_terms=_parse_metric_glossary(aka, metric_name=name),
                headings=set(subs.keys()),
                duplicate_headings=duplicates,
            )
        )
    return metrics


def _validate_metric_enum(
    value: str,
    aliases: dict[str, str],
    *,
    metric_label: str,
    heading: str,
) -> str | None:
    """Return an error when ``value`` is outside the closed vocabulary, else ``None``."""
    if aliases.get(value.strip().lower()):
        return None
    allowed = ", ".join(sorted({canonical for canonical in aliases.values()}))
    return (
        f"Metric '{metric_label}': #### {heading} is {value!r} — allowed values are "
        f"{allowed}"
    )


def _validate_metrics(metrics: list[ParsedMetric]) -> tuple[list[str], list[str]]:
    """Blocking errors + warnings for the ``## Metrics`` section (metric docs only).

    Requires 1–10 ``### {Metric Name}`` subsections, each carrying every heading in
    ``_METRIC_REQUIRED_H4`` plus a ``#### Golden Query`` SQL block. ``#### Type``,
    ``#### Direction``, ``#### Grain``, ``#### Is Additive`` and ``#### Business Stage``
    are closed vocabularies, checked whenever a value is present. ``#### MBR``,
    ``#### Category``, ``#### Acronym`` and ``#### Business Stage`` are optional but
    must not be present-and-empty.

    Names and slugs must be unique within the document: the slug is the key the
    generator phase will use to name the metric's table, and two metrics claiming it
    would silently collapse into one.
    """
    errors: list[str] = []
    warnings: list[str] = []
    if not metrics:
        errors.append(
            "Missing ## Metrics section with at least one ### metric subsection"
        )
        return errors, warnings
    if len(metrics) > _MAX_METRICS_PER_DOCUMENT:
        errors.append(
            f"## Metrics defines {len(metrics)} metrics — the maximum is "
            f"{_MAX_METRICS_PER_DOCUMENT} per document; split the extra metrics into "
            "another metric entity"
        )

    seen_names: set[str] = set()
    seen_slugs: set[str] = set()
    for metric in metrics:
        label = metric.name if not _is_placeholder(metric.name) else "(unnamed)"
        if _is_placeholder(metric.name):
            errors.append("A ### metric subsection is missing a real name")
        elif metric.name.lower() in seen_names:
            errors.append(
                f"Duplicate metric name '{metric.name}' — each ### subsection must "
                "name a distinct metric"
            )
        else:
            seen_names.add(metric.name.lower())

        for attr, heading in _METRIC_REQUIRED_H4:
            value = getattr(metric, attr)
            unfilled = not _section_has_content(value) or (
                attr not in _METRIC_PROSE_H4 and _is_placeholder(value)
            )
            if unfilled:
                errors.append(f"Metric '{label}' is missing a #### {heading}")

        if metric.slug and not _is_placeholder(metric.slug):
            if not _METRIC_SLUG_RE.match(metric.slug):
                errors.append(
                    f"Metric '{label}': #### Slug {metric.slug!r} must be snake_case "
                    "(lowercase letters, digits and underscores, starting with a letter)"
                )
            elif metric.slug in seen_slugs:
                errors.append(
                    f"Duplicate metric slug '{metric.slug}' — the slug is the stable "
                    "key for this metric and must be unique within the document"
                )
            else:
                seen_slugs.add(metric.slug)

        for attr, heading, aliases in (
            ("metric_type", "Type", _CATALOG_TYPE_ALIASES),
            ("direction", "Direction", _METRIC_DIRECTION_ALIASES),
            ("grain", "Grain", _METRIC_GRAIN_ALIASES),
            ("is_additive", "Is Additive", _METRIC_BOOLEAN_ALIASES),
            ("business_stage", "Business Stage", _METRIC_BUSINESS_STAGES),
        ):
            value = getattr(metric, attr)
            if not value or _is_placeholder(value):
                continue
            enum_error = _validate_metric_enum(
                value, aliases, metric_label=label, heading=heading
            )
            if enum_error:
                errors.append(enum_error)

        if metric.golden_query is None:
            errors.append(
                f"Metric '{label}' is missing a #### Golden Query with a SQL block"
            )

        for optional in _METRIC_OPTIONAL_H4:
            # ``headings`` is keyed by the normalized heading text, which only equals
            # the attribute name for single-word fields — ``business_stage`` is authored
            # as ``#### Business Stage``.
            if _METRIC_OPTIONAL_H4_LABELS[
                optional
            ].lower() in metric.headings and not _section_has_content(
                getattr(metric, optional)
            ):
                errors.append(
                    f"Metric '{label}': optional #### {_METRIC_OPTIONAL_H4_LABELS[optional]} "
                    "heading is present but empty — omit the heading when it does "
                    "not apply"
                )
        for duplicate in metric.duplicate_headings:
            warnings.append(
                f"Metric '{label}': #### {duplicate} is authored more than once — only "
                "the last block is read; merge them"
            )
        if _section_has_content(metric.category) and not _section_has_content(
            metric.mbr
        ):
            warnings.append(
                f"Metric '{label}': #### Category is set without a #### MBR — a "
                "category is the block a metric occupies inside an MBR agenda"
            )
    return errors, warnings


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


def _validate_legacy_metric_document(
    parsed: ParsedEntityDocument,
    sections: dict[str, str],
) -> tuple[list[str], list[str]]:
    """Validate a metric doc still written against the pre-redesign template.

    The two formats are accepted side by side for the whole migration: the 46 documents
    under ``docs/llm_context/metric_entities/`` are converted in a later pass, and until
    then a legacy doc that someone touches for an unrelated reason must not fail CI.
    It also decouples this repo's merge from the TARS authoring-plugin rollout — either
    can ship first. This branch is deleted once the migration lands.
    """
    errors: list[str] = []
    warnings: list[str] = []
    if not _section_has_content(_find_section(sections, "overview")):
        errors.append("Missing ## Overview section")
    dos_and_donts = _find_section(
        sections, "dos and don'ts", "dos and don", "do's and don"
    )
    if not _section_has_content(dos_and_donts):
        errors.append("Missing ## Dos and Don'ts section")
    elif not _has_do_and_dont(dos_and_donts):
        warnings.append("## Dos and Don'ts should list at least one Do and one Don't")
    if not parsed.golden_queries:
        errors.append("Missing ## Golden Queries with at least one SQL block")
    errors.extend(_validate_catalog_rows(parsed.catalog))
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
    errors.extend(
        _validate_optional_sections_not_empty(
            sections, optional_headings=_LEGACY_METRIC_OPTIONAL_SECTIONS
        )
    )
    return errors, warnings


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

    # ``## Description`` is the metric template's heading for what domain docs call
    # ``## Overview``. Both land on ``overview`` so every downstream reader — the DataHub
    # publisher, the tars-evals mock's product description and search text — keeps
    # working across the two formats without knowing which one it was handed.
    overview = _find_section(sections, "overview") or _find_section(
        sections, "description", exact_only=True
    )
    glossary_text = _find_section(sections, "glossary", "synonyms")
    tables_text = _find_section(sections, "tables", "where to query")
    golden_text = _find_section(
        sections, "golden queries", "golden query", exact_only=True
    )
    ownership_text = _find_section(sections, "ownership")
    mbr_text = _find_section(sections, "mbr")
    catalog_text = _find_section(sections, "catalog", exact_only=True)
    metrics_text = _find_section(sections, "metrics", exact_only=True)
    # ``exact_only`` — ``## Related Domain Entities`` contains "domain" and would
    # otherwise be read as the entity's domain.
    domain_text = _find_section(sections, "domain", exact_only=True)
    related_text = _find_section(sections, "related domain entities")
    superset_text = _find_section(sections, "superset golden assets", exact_only=True)

    glossary_terms = _parse_glossary(glossary_text)
    metric_dataset_rows = _parse_metric_dataset_rows(superset_text)
    datasets = _parse_datasets(tables_text)
    if not datasets and not metric_dataset_rows:
        datasets = _parse_datasets(markdown)
    metrics = _parse_metrics(metrics_text)
    # New metric template: aliases live under each metric's ``#### Also Known As``
    # instead of one entity-level ``## Glossary and Synonyms``. Flattening them into the
    # same document-level list keeps the published payload identical, so nothing
    # downstream has to know which template authored the document. A migrated document
    # carrying both contributes both — the per-metric terms come second so an entity-level
    # bullet stays first in the published order.
    for metric in metrics:
        glossary_terms.extend(metric.glossary_terms)
    # New metric template: golden queries live under each metric's ``#### Golden Query``,
    # not a top-level ``## Golden Queries`` section. They take precedence — a document
    # that defines ``## Metrics`` is authoritative about its own queries, and falling
    # back first would let one stray legacy ``## Golden query: …`` heading shadow every
    # per-metric query, so the CI gate (which reads ``parsed.golden_queries``) would
    # validate the leftover and skip the real ones.
    golden_queries = [m.golden_query for m in metrics if m.golden_query]
    if not golden_queries:
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
        metrics=metrics,
        domain=_scalar_field(domain_text),
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
    ``create-{metric,domain}-entity-doc`` skills, so a doc the skill (or the Luigi
    bot) tells an author to produce is exactly the doc this gate accepts.

    Both types share a small core: an H1 title, a ``## Ownership`` section and a
    ``## Glossary and Synonyms`` section. The rest differs by type:

    - **domain** — requires ``## Overview``, a Data Steward (no Data Owner role),
      ``## Tables`` (concrete ``schema.table``), ``## Key Metrics``,
      ``## Relationships with other entities``, ``## Dos and Don'ts`` and at least one
      ``## Golden Queries`` SQL block.
    - **metric** — requires ``## Description``, ``## Domain``, a Data Steward AND a Data
      Owner, and a ``## Metrics`` section holding 1–10 ``### {Metric Name}``
      subsections, each with ``#### Slug``, ``#### Description``,
      ``#### Also Known As``, ``#### Rules``, ``#### Type``, ``#### Direction``,
      ``#### Grain``, ``#### Is Additive`` and ``#### Golden Query``. ``## Related
      Domain Entities`` and ``## Targets and OKRs`` are optional; per-metric ``#### MBR``
      / ``#### Category`` are optional. ``#### Acronym`` and ``#### Business Stage`` are
      accepted for documents that carry them, but no template offers them.

    Domain docs have no Data Owner role at all — the steward is the single point of
    contact, and the template no longer offers the block. A Data Owner is still parsed
    and published when present, because 42 of the 60 domain docs written under the old
    template carry one and rejecting them would be a migration, not a validation.
    Metric docs still require both roles.

    A metric doc with no ``## Metrics`` heading is validated against the pre-redesign
    template instead (``_validate_legacy_metric_document``). Both formats are accepted
    for the whole migration window, so neither the doc migration nor the TARS authoring
    plugin has to land in a particular order relative to this repo.
    """
    is_metric = data_product_type == DATA_PRODUCT_TYPE_METRIC
    errors: list[str] = []
    warnings: list[str] = []
    sections = _split_sections(parsed.raw_markdown or "")

    # Shared core: an H1 title, an Ownership section, and a Glossary. Ownership always
    # needs a Data Steward; a Data Owner is a metric-doc role only. Domain docs dropped
    # the role entirely, but one authored under the old template is still accepted.
    if not parsed.title or parsed.title == "Untitled Entity":
        errors.append("Missing H1 title")
    if not parsed.has_ownership_section:
        errors.append("Missing ## Ownership section")
    else:
        if not parsed.owners.get("data_steward"):
            errors.append("Missing Data Steward email in ## Ownership section")
        if is_metric and not parsed.owners.get("data_owner"):
            errors.append("Missing Data Owner email in ## Ownership section")
    # A redesigned metric document carries its aliases per metric, under
    # ``#### Also Known As`` — the entity-level section is gone from that template, and
    # each metric's field is required in ``_validate_metrics``, so demanding both here
    # would reject every document the current questionnaire produces. Domain documents
    # and pre-redesign metric documents still own an entity-level glossary.
    glossary = _find_section(sections, "glossary and synonyms", "glossary", "synonyms")
    if not _section_has_content(glossary) and not (is_metric and parsed.metrics):
        errors.append("Missing ## Glossary and Synonyms section")

    if not is_metric:
        # Domain-specific: narrative Overview, routing by table, and a Dos and Don'ts.
        # Checked against the section, not ``parsed.overview`` — the latter also accepts
        # a metric doc's ``## Description``, which is not the domain heading.
        if not _section_has_content(_find_section(sections, "overview")):
            errors.append("Missing ## Overview section")
        dos_and_donts = _find_section(
            sections, "dos and don'ts", "dos and don", "do's and don"
        )
        if not _section_has_content(dos_and_donts):
            errors.append("Missing ## Dos and Don'ts section")
        elif not _has_do_and_dont(dos_and_donts):
            # Advisory (non-blocking): present and non-empty, but the authoring
            # guidance asks for at least one Do AND one Don't. Left to the reviewer.
            warnings.append(
                "## Dos and Don'ts should list at least one Do and one Don't"
            )
        if not parsed.datasets:
            errors.append("No schema.table references found in ## Tables section")
        key_metrics = _find_section(sections, "key metrics")
        if not _section_has_content(key_metrics):
            errors.append("Missing ## Key Metrics section")
        relationships = _relationships_section(sections)
        if not _section_has_content(relationships):
            errors.append("Missing ## Relationships with other entities section")
        if not parsed.golden_queries:
            errors.append("Missing ## Golden Queries with at least one SQL block")
        errors.extend(
            _validate_optional_sections_not_empty(
                sections, optional_headings=_DOMAIN_OPTIONAL_SECTIONS
            )
        )
        return errors, warnings

    # Metric-specific. Which contract applies is decided by the presence of a
    # ``## Metrics`` heading, not by a flag or a file list: a document carries its own
    # format, so a legacy doc and a migrated one can sit side by side in the same commit.
    if not _has_exact_section(sections, "metrics"):
        legacy_errors, legacy_warnings = _validate_legacy_metric_document(
            parsed, sections
        )
        errors.extend(legacy_errors)
        warnings.extend(legacy_warnings)
        return errors, warnings

    # Redesigned template: an entity-level Description and Domain plus a ## Metrics
    # section that holds one subsection per metric. Related Domain Entities is inferred
    # and optional; the OKR/Health classification moved from the old ## Catalog table
    # into each metric's #### Type, and ## Scope / ## Calculation are gone.
    description = _find_section(sections, "description", exact_only=True)
    if not _section_has_content(description):
        errors.append("Missing ## Description section")
    # Presence only. Whether the value is in the metadata domain allowlist is checked by
    # the CI entrypoint, which can import the registry — this module is deliberately
    # stdlib-only so tars-evals can load it by file path before any dependency install
    # (enforced by test_document_parser_and_its_siblings_are_stdlib_only).
    if not _section_has_content(parsed.domain) or _is_placeholder(parsed.domain):
        errors.append("Missing ## Domain section with the entity's metadata domain")
    metric_errors, metric_warnings = _validate_metrics(parsed.metrics)
    errors.extend(metric_errors)
    warnings.extend(metric_warnings)
    errors.extend(
        _validate_optional_sections_not_empty(
            sections, optional_headings=_METRIC_OPTIONAL_SECTIONS
        )
    )
    return errors, warnings
