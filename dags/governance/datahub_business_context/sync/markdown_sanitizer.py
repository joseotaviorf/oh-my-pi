"""Normalize markdown artifacts left by DataHub's rich-text Document editor.

DataHub's "Create Document" editor is not a plain-markdown textarea — content
pasted into it (often already formatted, e.g. from a Google Doc) survives as
artifacts its own markdown export can't express cleanly:

- Inline HTML for marks with no markdown equivalent (font-size spans,
  underline tags wrapped around link targets).
- Asterisk-decorated emphasis (``***_text_***``, ``*_text_*``, ``***text***``,
  ``*text*``) that renders as italic or bold+italic. House style is bold-only:
  any run involving an asterisk is normalized to ``**text**``; italic is
  reserved for a pure underscore run (``_text_``) with no asterisks, which is
  left untouched.
- Multiple list items collapsed onto a single physical line, with a bare
  ``-`` acting as the item separator instead of each item starting its own
  line — this breaks any parser expecting one bullet per line (see
  ``document_parser._parse_owners`` / ``_parse_glossary`` / ``_parse_mbr``).
  A bold pseudo-heading glued to the front (``**Data Owner:**- a- b``) is
  also split back onto its own line, with a blank line on both sides so the
  following bullets don't get absorbed into a preceding list.
- A heading marker (``##``/``###``) wrapped in bold (``**### Query 1**``)
  instead of being a real ATX heading, losing its heading semantics.
- A whole GFM table flattened onto one physical line, with row breaks
  collapsed to ``||`` (the closing pipe of one row meeting the opening pipe
  of the next, newline eaten) — this renders as raw text instead of a table.
- Code-fence delimiters glued to content (``` ```sqlSELECT … ORDER BY 1``` ```)
  instead of sitting on their own lines: the closing fence never matches, so
  the block never closes and swallows every section below it.

This module fixes exactly those six, structurally: every rule is a no-op on
markdown that doesn't contain the pattern, so it's safe to run on
hand-authored files too.

It deliberately does NOT try to restore whitespace the editor drops at
paragraph line-wrap boundaries (e.g. "thatmeasure" for "that measure"). That
loss has no reliable regex fix — the glued words are plain lowercase runs, in
mixed English/Portuguese prose, with no case/length signal to split on;
reconstructing them needs a dictionary and would risk introducing *wrong*
splits (worse than an obvious typo a reviewer can spot). Lost spaces also
break adjacent emphasis (``and***% Foo***`` won't render, because ``***``
can't open a run when preceded by a letter and followed by punctuation) —
same root cause, same limitation. It's called out in the generated PR's
review checklist instead (see ``github_delivery.open_sync_pull_request``),
for a human to catch by comparing the rendered PR diff against the source.
"""

from __future__ import annotations

import re

_FENCED_CODE_RE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE_RE = re.compile(r"`[^`\n]+`")
_CODE_PLACEHOLDER = "\x00CODE{}\x00"

# Language tags DataHub glues onto a fence's opening (```sqlSELECT …). Only
# needed to peel a known tag off the first content token; unknown tags stay
# as content. Ordered longest-first so a longer name wins over a shorter prefix
# of it (``sqlite`` must be tried before ``sql``, else ```` ```sqlite ```` is
# mis-read as ``sql`` glued to ``ite``).
_KNOWN_FENCE_LANGS = ("sqlite", "python", "bash", "yaml", "json", "text", "sql", "sh")

_SPAN_RE = re.compile(r"<span\b[^>]*>(.*?)</span>", re.IGNORECASE | re.DOTALL)
_U_TAG_RE = re.compile(r"</?u>", re.IGNORECASE)

# Emphasis house style: BOLD is the default; italic is reserved exclusively for
# a pure underscore run (``_x_``) with no asterisks. DataHub's editor emits
# asterisk-decorated emphasis (``*_x_*``, ``***_x_***``, ``***x***``, ``*x*``)
# that renders as italic or bold+italic; every run that involves an asterisk is
# collapsed to plain bold ``**x**``, dropping the italic layer. A bare ``_x_``
# (no asterisk) is left untouched so intentional italic still works.
#
# Applied longest-delimiter-first. The asterisk-wrapped-underscore form covers
# 1-3 leading/trailing asterisks in one pass; the triple-asterisk form catches
# bold+italic without an inner underscore; the single-asterisk form catches
# plain ``*x*`` italic (guarded so it never bites into ``**``/``***`` runs).
_ASTERISK_UNDERSCORE_EMPHASIS_RE = re.compile(r"\*{1,3}_(.+?)_\*{1,3}")
_BOLD_ITALIC_TRIPLE_RE = re.compile(r"\*\*\*(.+?)\*\*\*")
_SINGLE_ITALIC_ASTERISK_RE = re.compile(r"(?<!\*)\*(?!\*)([^*\n]+?)(?<!\*)\*(?!\*)")

# A "-" acting as a glued bullet separator: a hyphen with NO space before it
# (attached to the end of the previous item) and whitespace after it — the
# exact shape DataHub produces when it flattens a list ("itemA- itemB").
# Requiring the absence of a leading space is what distinguishes it from a
# prose dash ("A - B", spaced both sides), which must be left alone.
_MID_LINE_BULLET_RE = re.compile(r"(?<=\S)-\s+(?=\S)")

# An ATX heading marker DataHub wrapped in bold instead of emitting as a real
# heading. Requires a space after the hashes (like a real ATX heading) so a
# literal bold "**#1 priority**" is never touched.
_BOLD_WRAPPED_HEADING_RE = re.compile(r"^\*\*(#{1,6}\s+\S.*?)\*\*[ \t]*$", re.MULTILINE)

# A GFM table row boundary flattened to "||": the closing pipe of one row and
# the opening pipe of the next, with the newline between them eaten. Two pipes
# separated only by spaces on a table line never occur in a well-formed row
# (an empty cell would still hold content-less text between distinct separator
# pipes on the SAME row) so this is a safe row-split marker for the collapsed
# tables DataHub produces. Heuristic caveat: a genuinely empty cell written as
# "| |" on a collapsed line would be split too — none of the TARS docs use them.
_TABLE_ROW_JOIN_RE = re.compile(r"\|[ \t]*\|")


def _normalize_code_fences(markdown: str) -> str:
    """Put mangled code-fence delimiters back on their own lines.

    DataHub's editor glues the opening ``` to its first content token (and any
    language tag) and the closing ``` to the last content token, e.g.
    ``` ```sqlSELECT … ORDER BY 1``` ```. A closing fence with text before it is
    not a valid CommonMark closing fence, so the block never closes and swallows
    every section below it; a glued opening turns the first content line into an
    invisible info string. Rewrite each block to a canonical
    ``` ```lang\\n<content>\\n``` ``` form, wrapped in blank lines so it always
    renders as its own block.

    Runs before :func:`_shield_code` so the shielded/restored block is the
    repaired one.
    """

    def _fix(match: re.Match[str]) -> str:
        inner = match.group(0)[3:-3]  # strip the opening/closing ``` delimiters
        lang = ""
        for candidate in _KNOWN_FENCE_LANGS:
            if not inner.lower().startswith(candidate):
                continue
            after = inner[len(candidate) :]
            boundary = after[:1]
            # Only treat the prefix as a language tag when what follows is a
            # clear boundary — never a lowercase letter/digit/underscore, which
            # would mean the word continues (a longer language name, or a genuine
            # glue like ```sqlis_eviction that we must NOT split mid-word).
            if boundary in ("", "\n", " ", "\t"):
                # proper tag: ```lang, ```lang\n…, or ```lang <code>
                lang, inner = inner[: len(candidate)], after.lstrip(" \t\n")
            elif boundary.isupper() or (not boundary.isalnum() and boundary != "_"):
                # glued code that clearly isn't a continuation of the tag word:
                # ```sqlSELECT (uppercase) or ```sql( (punctuation)
                lang, inner = inner[: len(candidate)], after
            break
        body = inner.strip("\n").rstrip()
        return f"\n```{lang}\n{body}\n```\n"

    return _FENCED_CODE_RE.sub(_fix, markdown)


def _shield_code(markdown: str) -> tuple[str, list[str]]:
    blocks: list[str] = []

    def _stash(match: re.Match[str]) -> str:
        blocks.append(match.group(0))
        return _CODE_PLACEHOLDER.format(len(blocks) - 1)

    markdown = _FENCED_CODE_RE.sub(_stash, markdown)
    markdown = _INLINE_CODE_RE.sub(_stash, markdown)
    return markdown, blocks


def _unshield_code(markdown: str, blocks: list[str]) -> str:
    for idx, block in enumerate(blocks):
        markdown = markdown.replace(_CODE_PLACEHOLDER.format(idx), block)
    return markdown


def _reflow_inline_bullets(markdown: str) -> str:
    """Split lines where DataHub glued multiple bullet items together.

    A heading like ``**Data Owner:**`` immediately followed inline by several
    ``- `` items is split into the heading on its own line plus one bullet per
    line; a bullet list whose first item is intact but later items got glued
    on (``- A, B → x- C, D → y``) is split into one item per line.

    Only two line shapes are reflowed, so a prose paragraph that happens to
    contain a glue-like dash is never mistaken for a list: a line that already
    starts with ``- `` (a real bullet), or a non-bullet line whose first
    segment is a bold pseudo-heading ending in ``:``. Any other line is left
    untouched even if it contains ``word- word``.
    """
    out_lines: list[str] = []
    for line in markdown.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith(("|", "```", "#")):
            out_lines.append(line)
            continue
        indent = line[: len(line) - len(line.lstrip())]
        starts_as_bullet = stripped.startswith("- ")
        body = stripped[2:] if starts_as_bullet else stripped
        pieces = [p.strip() for p in _MID_LINE_BULLET_RE.split(body) if p.strip()]
        if len(pieces) <= 1:
            out_lines.append(line)
            continue
        heading = None
        if not starts_as_bullet:
            # A non-bullet line is only a glued list when its first segment is a
            # bold pseudo-heading (``**Data Owner:**``). Otherwise it is prose
            # with an inline dash — leave it exactly as it was.
            if pieces[0].rstrip("*_ ").endswith(":"):
                heading, pieces = pieces[0], pieces[1:]
            else:
                out_lines.append(line)
                continue
        if heading:
            # Blank line BEFORE the heading too, so a heading glued right after
            # a previous group's last bullet (``- foo\n**Data Steward:**``) is
            # not swallowed as a lazy continuation of that list.
            if out_lines and out_lines[-1].strip():
                out_lines.append("")
            out_lines.append(f"{indent}{heading}")
            out_lines.append("")
        out_lines.extend(f"{indent}- {p}" for p in pieces)
    return "\n".join(out_lines)


def _reflow_collapsed_tables(markdown: str) -> str:
    """Split a GFM table DataHub flattened onto one line back into rows.

    A collapsed table is a single physical line starting with ``|`` where every
    row break became ``||``. Splitting on that marker restores one row per line;
    a blank line is inserted before the block so GFM recognizes it as a table
    (a preceding hard-break paragraph would otherwise keep it inline).
    """
    out_lines: list[str] = []
    for line in markdown.split("\n"):
        stripped = line.strip()
        if not (stripped.startswith("|") and _TABLE_ROW_JOIN_RE.search(stripped)):
            out_lines.append(line)
            continue
        indent = line[: len(line) - len(line.lstrip())]
        rows = _TABLE_ROW_JOIN_RE.sub("|\n|", stripped).split("\n")
        if out_lines and out_lines[-1].strip():
            out_lines.append("")
        out_lines.extend(f"{indent}{row.strip()}" for row in rows)
    return "\n".join(out_lines)


def sanitize_datahub_markdown(markdown: str) -> str:
    """Normalize known DataHub rich-text-editor export artifacts.

    Safe to call on already-clean, hand-authored markdown — every rule is a
    no-op when its pattern isn't present. Fenced/inline code is shielded so
    the emphasis and bullet rules never touch code content.
    """
    # Repair mangled code fences first, then shield the now-canonical blocks so
    # the rest of the rules leave them alone.
    markdown = _normalize_code_fences(markdown)
    protected, code_blocks = _shield_code(markdown)

    protected = _SPAN_RE.sub(r"\1", protected)
    protected = _U_TAG_RE.sub("", protected)
    # Unwrap bold-wrapped headings before normalizing emphasis so the heading's
    # own ``**`` markers aren't mistaken for emphasis.
    protected = _BOLD_WRAPPED_HEADING_RE.sub(r"\1", protected)
    # Emphasis → bold-only house style (see the regex block above). Longest
    # delimiter first: asterisk+underscore, then triple-asterisk, then single.
    protected = _ASTERISK_UNDERSCORE_EMPHASIS_RE.sub(r"**\1**", protected)
    protected = _BOLD_ITALIC_TRIPLE_RE.sub(r"**\1**", protected)
    protected = _SINGLE_ITALIC_ASTERISK_RE.sub(r"**\1**", protected)
    protected = _reflow_collapsed_tables(protected)
    protected = _reflow_inline_bullets(protected)

    return _unshield_code(protected, code_blocks)
