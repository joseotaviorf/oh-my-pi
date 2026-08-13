#!/usr/bin/env python3
"""Resolve which tars-evals dataset stems a git diff affects.

Stdlib-only so CI can call this before ``uv sync``. Diff-base resolution
mirrors ``bietlejuice.ci.ci_diff_ref`` but is reimplemented here because this
standalone package cannot depend on the workspace.

Two changed-doc directories are tracked:

- ``docs/llm_context/metric_entities/<stem>.md`` maps 1:1 to a dataset stem.
- ``docs/llm_context/business_entities/<stem>.md`` fans out to related metric
  stems via a reverse index over metric docs' ``## Related Business Entities``
  plus the business doc's own ``## Related Metric Entities`` back-links. When a
  changed business doc resolves to zero metric stems, the run **warns and skips**
  eval/drift for that doc (merge allowed) instead of fail-closed fan-out to every
  dataset stem in the repo.

Two stem lists are emitted:

- **eval stems** — in-scope stems that have a dataset file today.
- **scope stems** — every in-scope stem, including docs with no dataset yet
  and deleted docs (used to prune stale auto-generated datasets).

A metric doc modified *only* inside an eval-irrelevant H2 section (see
``_EVAL_IRRELEVANT_H2``) is dropped from the **eval** list but kept in the
**scope** list: a Data Steward email edit cannot change what SQL is correct,
so it must not cost a ~4-minute, ~1.7M-token re-evaluation nor block the PR on
an LLM judge's opinion of SQL the author never touched. The drift check is
cheap and stays broad. The filter only ever shrinks the scope on positive
evidence — additions, deletions, renames and unreadable blobs still evaluate.

Exit codes: 0 = resolved (empty scope is valid); 2 = structural error or
sample budget exceeded. Exit code 1 is reserved for ``build_rollup.py`` gate
failures.

Usage:
    uv run python scripts/changed_dataset_stems.py
    uv run python scripts/changed_dataset_stems.py --base origin/master --head HEAD
    uv run python scripts/changed_dataset_stems.py --print scope
    uv run python scripts/changed_dataset_stems.py \
        --write-eval-stems .tars-eval-stems \
        --write-scope-stems .tars-eval-expected-stems
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# The only first-party import: repo_bootstrap.py is itself stdlib-only (see
# its own imports) and locates + live-loads document_parser.py, which is also
# stdlib-only. See tests/test_changed_dataset_stems_contract.py for a guard
# that keeps this promise from silently rotting.
_SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from tars_evals.repo_bootstrap import load_document_parser, repo_root  # noqa: E402

_DEFAULT_MAX_SAMPLES = 60
_TEMPLATE_NAME = "_TEMPLATE.md"
_METRIC_PREFIX = "docs/llm_context/metric_entities/"
_BUSINESS_PREFIX = "docs/llm_context/business_entities/"
_LONG_LIVED_BRANCHES = frozenset({"master", "forno"})


class GitDiffError(RuntimeError):
    """A git subprocess invocation needed to resolve the diff failed."""


class DiffParseError(ValueError):
    """``git diff --name-status -z`` output could not be parsed."""


class BudgetExceededError(RuntimeError):
    """The resolved eval scope's total sample count exceeds the budget."""

    def __init__(
        self, *, total_samples: int, max_samples: int, stems: list[str]
    ) -> None:
        self.total_samples = total_samples
        self.max_samples = max_samples
        self.stems = stems
        super().__init__(
            f"sample budget exceeded: {total_samples} sample(s) across "
            f"{len(stems)} stem(s) > TARS_EVAL_MAX_SAMPLES={max_samples}"
        )


# --------------------------------------------------------------------------
# 2.1 — diff-base resolution
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class DiffRange:
    base: str
    head: str
    dotted: str  # "..." (merge-base diff) or ".." (literal commit range)
    mode: str  # "explicit" | "pr" | "push" | "fallback" — for diagnostics/tests


def _is_pull_request(env: Mapping[str, str]) -> bool:
    return env.get("CI_PIPELINE_EVENT", "").strip() == "pull_request"


def _nonzero_sha(value: str | None) -> str | None:
    """Return ``value`` unless it's unset/blank or git's all-zero placeholder SHA."""
    if not value:
        return None
    stripped = value.strip()
    if not stripped or set(stripped) == {"0"}:
        return None
    return stripped


def resolve_diff_range(
    *,
    env: Mapping[str, str],
    explicit_base: str | None = None,
    explicit_head: str | None = None,
) -> DiffRange:
    """Resolve the git diff range to scan for changed context docs.

    Precedence:
      1. ``explicit_base``/``explicit_head`` (either given) — literal two-dot
         range, exactly as passed. Intended for local/manual invocation.
      2. ``CI_PIPELINE_EVENT=pull_request`` — ``origin/master...HEAD``
         (three-dot / merge-base), so a long-running PR branch is diffed
         against where it forked from ``master``, not against master's tip.
      3. ``CI_PREV_COMMIT_SHA`` set (push event) — ``CI_PREV_COMMIT_SHA..
         CI_COMMIT_SHA`` (two-dot, literal), which correctly scopes a
         multi-commit push in one shot. Callers must still run
         :func:`ensure_usable_diff_range` before ``git diff``: Woodpecker
         sometimes supplies a prev SHA that is not in the master clone
         (e.g. a squash-merge's pre-squash PR tip).
      4. Fallback — ``HEAD~1..HEAD``, for local runs or a first push with no
         previous SHA.
    """
    if explicit_base is not None or explicit_head is not None:
        return DiffRange(
            base=explicit_base or "HEAD~1",
            head=explicit_head or "HEAD",
            dotted="..",
            mode="explicit",
        )

    if _is_pull_request(env):
        return DiffRange(base="origin/master", head="HEAD", dotted="...", mode="pr")

    prev_sha = _nonzero_sha(env.get("CI_PREV_COMMIT_SHA"))
    if prev_sha is not None:
        head = env.get("CI_COMMIT_SHA", "").strip() or "HEAD"
        return DiffRange(base=prev_sha, head=head, dotted="..", mode="push")

    return DiffRange(base="HEAD~1", head="HEAD", dotted="..", mode="fallback")


# --------------------------------------------------------------------------
# git diff invocation (I/O)
# --------------------------------------------------------------------------


def _git_commit_exists(
    sha: str,
    *,
    cwd: Path,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> bool:
    """True when ``sha`` resolves to a commit object in the local repo."""
    result = run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
        cwd=cwd,
        check=False,
        capture_output=True,
    )
    return result.returncode == 0


def _git_is_ancestor(
    maybe_ancestor: str,
    head: str,
    *,
    cwd: Path,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> bool:
    """True when ``maybe_ancestor`` is an ancestor of ``head``."""
    result = run(
        ["git", "merge-base", "--is-ancestor", maybe_ancestor, head],
        cwd=cwd,
        check=False,
        capture_output=True,
    )
    return result.returncode == 0


def ensure_usable_diff_range(
    diff_range: DiffRange,
    *,
    cwd: Path,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> tuple[DiffRange, str | None]:
    """Rewrite unusable push-mode ranges to ``HEAD~1..HEAD``.

    After a squash-merge to ``master``, Woodpecker has been observed setting
    ``CI_PREV_COMMIT_SHA`` to the pre-squash PR-branch tip (or another
    branch's tip). That object is absent from a master-only CI clone, so
    ``git diff PREV..HEAD`` fails with ``Invalid revision range``. Falling
    back to ``HEAD~1..HEAD`` correctly scopes a single squash-merge commit.

    Non-push modes are returned unchanged. Returns ``(range, warning)`` where
    ``warning`` is set only when a rewrite happened.
    """
    if diff_range.mode != "push":
        return diff_range, None
    if _git_commit_exists(diff_range.base, cwd=cwd, run=run) and _git_is_ancestor(
        diff_range.base, diff_range.head, cwd=cwd, run=run
    ):
        return diff_range, None
    warning = (
        f"CI_PREV_COMMIT_SHA={diff_range.base} is missing from the clone or "
        f"not an ancestor of {diff_range.head}; falling back to HEAD~1..HEAD"
    )
    return (
        DiffRange(base="HEAD~1", head="HEAD", dotted="..", mode="fallback"),
        warning,
    )


def run_git_diff(
    diff_range: DiffRange,
    *,
    cwd: Path,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> bytes:
    """Run ``git diff --name-status -z`` for ``diff_range``, returning raw stdout.

    Best-effort fetches ``origin/master`` first for PR-mode (three-dot) diffs,
    mirroring ``run_validation_by_domain.py``'s convention — a shallow or
    stale local ``origin/master`` must not silently under-scope a PR diff.
    """
    if diff_range.mode == "pr":
        run(
            ["git", "fetch", "--no-tags", "origin", "+refs/heads/master"],
            cwd=cwd,
            check=False,
            capture_output=True,
        )
    cmd = [
        "git",
        "diff",
        "--name-status",
        "-z",
        f"{diff_range.base}{diff_range.dotted}{diff_range.head}",
    ]
    try:
        result = run(cmd, cwd=cwd, check=True, capture_output=True)
    except subprocess.CalledProcessError as error:
        stderr = (error.stderr or b"").decode("utf-8", errors="replace").strip()
        raise GitDiffError(
            f"git diff failed for range "
            f"{diff_range.base}{diff_range.dotted}{diff_range.head}: "
            f"{stderr or error}"
        ) from error
    except FileNotFoundError as error:
        raise GitDiffError(f"git executable not found: {error}") from error
    return result.stdout


# --------------------------------------------------------------------------
# 2.2 — git diff --name-status -z parsing + path classification
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class DiffEntry:
    status: str  # single-letter status (A/M/D/R/C/T/U/X/...), score digits stripped
    path: str  # new path (or the only path, for non-rename/copy statuses)
    old_path: str | None = None  # previous path, only set for R/C


def parse_name_status_z(raw: bytes) -> list[DiffEntry]:
    """Parse ``git diff --name-status -z`` output into :class:`DiffEntry` records.

    ``-z`` NUL-terminates every field instead of using newlines, and rename
    (``R``) / copy (``C``) records emit *three* NUL-terminated fields (status,
    old path, new path) instead of two — the one place this format is fiddly
    enough to deserve its own parser and unit tests.
    """
    if not raw:
        return []
    text = raw.decode("utf-8", errors="replace")
    fields = text.split("\0")
    if fields and fields[-1] == "":
        fields = fields[:-1]

    entries: list[DiffEntry] = []
    i = 0
    while i < len(fields):
        status_field = fields[i]
        if not status_field:
            raise DiffParseError(
                f"malformed git diff -z output: empty status field at position {i}"
            )
        status = status_field[0]
        if status in ("R", "C"):
            if i + 2 >= len(fields):
                raise DiffParseError(
                    f"malformed git diff -z output: truncated {status} record "
                    f"at position {i} (expected old path + new path)"
                )
            entries.append(
                DiffEntry(status=status, path=fields[i + 2], old_path=fields[i + 1])
            )
            i += 3
        else:
            if i + 1 >= len(fields):
                raise DiffParseError(
                    f"malformed git diff -z output: truncated {status} record "
                    f"at position {i} (expected a path)"
                )
            entries.append(DiffEntry(status=status, path=fields[i + 1]))
            i += 2
    return entries


@dataclass(frozen=True)
class ClassifiedDiff:
    metric_entries: tuple[DiffEntry, ...]
    business_entries: tuple[DiffEntry, ...]


def _is_context_doc(path: str | None, prefix: str) -> bool:
    if not path or not path.startswith(prefix):
        return False
    rest = path[len(prefix) :]
    return rest.endswith(".md") and "/" not in rest and rest != _TEMPLATE_NAME


def classify_paths(entries: Iterable[DiffEntry]) -> ClassifiedDiff:
    """Partition diff entries into metric_entities / business_entities changes.

    Everything else (unrelated repo paths) is silently dropped. A rename's
    old and new path are both considered, so a doc renamed into or out of a
    tracked directory is still classified correctly.
    """
    metric: list[DiffEntry] = []
    business: list[DiffEntry] = []
    for entry in entries:
        candidates = [entry.path, entry.old_path]
        if any(_is_context_doc(p, _METRIC_PREFIX) for p in candidates):
            metric.append(entry)
        if any(_is_context_doc(p, _BUSINESS_PREFIX) for p in candidates):
            business.append(entry)
    return ClassifiedDiff(
        metric_entries=tuple(metric), business_entries=tuple(business)
    )


# --------------------------------------------------------------------------
# 2.3 — metric doc -> stem resolution
# --------------------------------------------------------------------------


def metric_stems_from_entries(
    entries: Iterable[DiffEntry],
) -> tuple[set[str], set[str]]:
    """Return ``(changed_stems, deleted_stems)`` from classified metric entries.

    A pure deletion contributes only to ``deleted_stems``. A rename whose new
    path is still a metric doc contributes its new stem to ``changed_stems``;
    a rename *out* of ``metric_entities/`` (old path matched here via
    ``classify_paths``, new path doesn't) contributes only its old stem to
    ``deleted_stems`` — the new path is no longer a metric doc and must not
    be queued for eval. Either way, a rename's old stem is always pruned.
    """
    changed: set[str] = set()
    deleted: set[str] = set()
    for entry in entries:
        if entry.status == "D":
            deleted.add(Path(entry.path).stem)
            continue
        if entry.status == "R" and entry.old_path:
            deleted.add(Path(entry.old_path).stem)
            if not _is_context_doc(entry.path, _METRIC_PREFIX):
                continue
        changed.add(Path(entry.path).stem)
    return changed, deleted


# --------------------------------------------------------------------------
# 2.4 — business-entity fan-out
# --------------------------------------------------------------------------


def load_metric_docs(metric_entities_dir: Path) -> dict[str, str]:
    """I/O: read every non-template metric doc on disk into ``{stem: text}``."""
    docs: dict[str, str] = {}
    if not metric_entities_dir.is_dir():
        return docs
    for md in sorted(metric_entities_dir.glob("*.md")):
        if md.name == _TEMPLATE_NAME:
            continue
        docs[md.stem] = md.read_text(encoding="utf-8")
    return docs


def build_reverse_index(
    docs: Mapping[str, str],
    *,
    parse_markdown: Callable[..., Any],
) -> dict[str, set[str]]:
    """Pure: invert every metric doc's ``## Related Business Entities`` field.

    Returns ``{business_kebab_id: {metric_stem, ...}}``. This is the
    authoritative direction — ``document_parser.parse_entity_markdown``
    parses ``related_data_products`` from metric docs only; there is no
    equivalent parsed field on the business side.
    """
    index: dict[str, set[str]] = {}
    for stem, text in docs.items():
        parsed = parse_markdown(text, fallback_title=stem)
        for business_id in parsed.related_data_products:
            index.setdefault(business_id, set()).add(stem)
    return index


_H2_RE = re.compile(r"^##\s+(.+)$", re.MULTILINE)


def _split_h2_sections(markdown: str) -> dict[str, str]:
    """Minimal local H2 splitter: lowercased heading -> body text.

    Deliberately duplicated (not imported) from
    ``document_parser._split_sections`` — that function is private API of a
    module we don't own, and this only needs one heading, not the full
    section-splitting behavior (DataHub escaping, H3 sub-parsing, etc).
    """
    matches = list(_H2_RE.finditer(markdown))
    sections: dict[str, str] = {}
    for idx, match in enumerate(matches):
        title = match.group(1).strip().lower()
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(markdown)
        sections[title] = markdown[start:end].strip()
    return sections


# --------------------------------------------------------------------------
# eval-relevance filter (metadata-only edits)
# --------------------------------------------------------------------------

# H2 sections that cannot change what SQL is correct for a metric, so editing
# only these must not spend ~4 minutes and ~1.7M tokens re-evaluating the stem.
# Deliberately tiny and conservative: every other section (Overview, Scope,
# Calculation, Glossary, Dos and Don'ts, …) feeds the context TARS reads when
# it writes the query, so a change there still triggers an eval. Anything we
# cannot classify falls through to "evaluate".
_EVAL_IRRELEVANT_H2 = frozenset({"ownership", "changelog"})


def strip_h2_sections(markdown: str, headings: frozenset[str]) -> str:
    """Return ``markdown`` with the named H2 sections (heading + body) removed."""
    matches = list(_H2_RE.finditer(markdown))
    if not matches:
        return markdown
    kept: list[str] = [markdown[: matches[0].start()]]
    for idx, match in enumerate(matches):
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(markdown)
        if match.group(1).strip().lower() not in headings:
            kept.append(markdown[match.start() : end])
    return "".join(kept)


def is_metadata_only_change(old_text: str, new_text: str) -> bool:
    """True when two doc revisions differ *only* inside eval-irrelevant sections.

    Used to drop a stem from the eval scope while leaving it in the drift
    scope: the drift check is cheap and must stay broad, but a Data Steward
    email edit should not block a PR on an LLM judge's opinion of unrelated SQL.
    """
    if old_text == new_text:
        return True
    return strip_h2_sections(old_text, _EVAL_IRRELEVANT_H2) == strip_h2_sections(
        new_text, _EVAL_IRRELEVANT_H2
    )


def resolve_old_ref(
    diff_range: DiffRange,
    *,
    cwd: Path,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> str | None:
    """The ref holding the *pre-change* blobs for ``diff_range``.

    For a three-dot (merge-base) range that is the merge base itself, not
    ``base``'s tip — otherwise unrelated master commits would look like part
    of this PR's change. Returns ``None`` when it can't be resolved, which
    callers must treat as "evaluate anyway".
    """
    if diff_range.dotted != "...":
        return diff_range.base
    result = run(
        ["git", "merge-base", diff_range.base, diff_range.head],
        cwd=cwd,
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.decode("utf-8", errors="replace").strip() or None


def read_blob_at(
    ref: str | None,
    path: str,
    *,
    cwd: Path,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> str | None:
    """``git show <ref>:<path>``, or ``None`` if it can't be read."""
    if ref is None:
        return None
    result = run(
        ["git", "show", f"{ref}:{path}"], cwd=cwd, check=False, capture_output=True
    )
    if result.returncode != 0:
        return None
    return result.stdout.decode("utf-8", errors="replace")


def find_metadata_only_stems(
    entries: Iterable[DiffEntry],
    *,
    repo_root: Path,
    old_ref: str | None,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> set[str]:
    """Stems whose modification touched only eval-irrelevant sections.

    Only plain modifications (``M``) are considered. Additions, deletions and
    renames always evaluate, and any doc whose old or new text can't be read
    falls through to evaluating — the filter may only ever *shrink* the scope
    on positive evidence.
    """
    metadata_only: set[str] = set()
    for entry in entries:
        if entry.status != "M":
            continue
        old_text = read_blob_at(old_ref, entry.path, cwd=repo_root, run=run)
        if old_text is None:
            continue
        try:
            new_text = (repo_root / entry.path).read_text(encoding="utf-8")
        except OSError:
            continue
        if is_metadata_only_change(old_text, new_text):
            metadata_only.add(Path(entry.path).stem)
    return metadata_only


def parse_related_metric_entities(markdown: str) -> list[str] | None:
    """Parse a business doc's own ``## Related Metric Entities`` bullets.

    Converts Title Case display names (e.g. ``- NPS FR``) into metric-doc
    stems (``nps_fr``) using the same bullet syntax as
    ``document_parser._parse_related_data_products``, but slugifying to
    snake_case (matching metric filenames) instead of kebab-case.

    Returns ``None`` when the heading is absent, OR when it is present but
    empty (no bullets, or only comments/whitespace) — both are "no
    information from this doc," and the caller must still fail closed. This
    matches the orphan-fixture contract in
    ``tests/fixtures/llm_context/business_orphan.md`` /
    ``test_orphan_business_doc_fails_closed_and_budget_aborts``: a heading
    with nothing filled in looks identical to an unfinished template, so it
    is deliberately NOT treated as a resolved "zero relationships" answer.

    Returns a list — possibly empty — only when the section contains an
    explicit sentinel bullet whose text starts with "none" (case-insensitive,
    optionally wrapped in ``()``/``**``, e.g. ``- None`` or
    ``- None — no metric entity doc references this domain as of 2026-08.``).
    That is an unambiguous, authored declaration of zero relationships,
    distinct from an empty/omitted section, and lets ``fan_out`` resolve the
    doc without falling back to evaluating every dataset stem in the repo
    (see the Agents-domain incident this fixes: PR #27459).

    A bare HTML comment line (``<!-- ... -->``) is ignored (not parsed as a
    stem or a sentinel), so a doc can add supplementary notes without them
    becoming bogus stems.
    """
    sections = _split_h2_sections(markdown)
    if "related metric entities" not in sections:
        return None
    body = sections["related metric entities"]
    stems: list[str] = []
    seen: set[str] = set()
    explicit_none = False
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("<!--") and stripped.endswith("-->"):
            continue
        if stripped.startswith("- "):
            name = stripped[2:].strip().strip("*").strip()
        else:
            name = stripped.strip("*").strip()
        if name.strip("()").strip().lower().startswith("none"):
            explicit_none = True
            continue
        stem = re.sub(r"[^a-zA-Z0-9]+", "_", name.strip().lower()).strip("_")
        if stem and stem not in seen:
            seen.add(stem)
            stems.append(stem)
    if not stems and not explicit_none:
        return None
    return stems


def business_kebab_id(stem: str) -> str:
    """File-stem -> kebab business id, matching ``document_parser``'s
    ``_display_name_to_product_id`` convention (e.g. ``house_and_listing`` ->
    ``house-and-listing``, the id a metric doc's own bullet would produce).
    """
    return stem.replace("_", "-")


def fan_out(
    business_entries: Iterable[DiffEntry],
    *,
    reverse_index: Mapping[str, set[str]],
    read_business_doc: Callable[[DiffEntry], str | None],
) -> tuple[set[str], list[str]]:
    """Resolve changed business docs to metric stems.

    ``read_business_doc`` returns the current markdown text for a changed
    business doc, or ``None`` when it can't be read (e.g. the doc was
    deleted). Returns ``(fanned_out_metric_stems, unresolved_business_stems)``
    — a non-empty ``unresolved_business_stems`` is surfaced as a CI warning and
    does not expand scope to every dataset stem (see ``resolve_scope``).

    A doc whose ``## Related Metric Entities`` section contains an explicit
    ``- None`` sentinel (``parse_related_metric_entities`` returns ``[]``, not
    ``None``) is resolved with zero fanned-out stems and is never unresolved.
    """
    fanned: set[str] = set()
    unresolved: list[str] = []
    for entry in business_entries:
        lookup_stems = [Path(entry.path).stem]
        if entry.old_path:
            lookup_stems.append(Path(entry.old_path).stem)
        text = read_business_doc(entry)
        own_backlinks = parse_related_metric_entities(text) if text else None
        reverse_matches: set[str] = set()
        for lookup_stem in lookup_stems:
            reverse_matches |= set(reverse_index.get(business_kebab_id(lookup_stem), ()))
        if own_backlinks is None:
            matched = reverse_matches
            if not matched:
                unresolved.append(Path(entry.path).stem)
        else:
            matched = set(own_backlinks) | reverse_matches
        fanned |= matched
    return fanned, unresolved


# --------------------------------------------------------------------------
# 2.5 — sample counting + budget guard
# --------------------------------------------------------------------------

_ITEMS_KEY_RE = re.compile(r"^items:\s*(?:#.*)?$")
_LIST_ITEM_RE = re.compile(r"^([ \t]*)-\s")


def count_items_in_text(text: str) -> int:
    """Count top-level ``items:`` list entries without a YAML parser dependency.

    Dataset files come in two indentation shapes — generator output starts
    each item at column 0 (``items:\\n- id: ...``); hand-authored files often
    indent items under the key (``items:\\n  - id: ...``). This locates the
    ``items:`` key, takes the *first* list-item line's indent as the item
    level, and counts only lines at exactly that indent — deeper indent is an
    item's own nested/multi-line field (e.g. an ``expected_query: |`` block
    scalar), never a sibling item, for well-formed YAML.
    """
    saw_items = False
    item_indent: str | None = None
    count = 0
    for line in text.splitlines():
        if not saw_items:
            if _ITEMS_KEY_RE.match(line):
                saw_items = True
            continue
        match = _LIST_ITEM_RE.match(line)
        if not match:
            continue
        indent = match.group(1)
        if item_indent is None:
            item_indent = indent
        if indent == item_indent:
            count += 1
    return count


def count_items(dataset_path: Path) -> int:
    """I/O wrapper: :func:`count_items_in_text` over a dataset file on disk."""
    return count_items_in_text(dataset_path.read_text(encoding="utf-8"))


def total_sample_count(stems: Iterable[str], *, datasets_dir: Path) -> int:
    total = 0
    for stem in stems:
        path = datasets_dir / f"{stem}.yaml"
        if path.is_file():
            total += count_items(path)
    return total


def apply_budget(total_samples: int, *, max_samples: int, stems: list[str]) -> None:
    """Fail loudly when ``total_samples`` exceeds ``max_samples``.

    Never silently truncates the eval scope — an overflow must be visible and
    force a decision (split the PR, or deliberately raise the limit), not
    quietly reduce gate coverage.
    """
    if total_samples > max_samples:
        raise BudgetExceededError(
            total_samples=total_samples, max_samples=max_samples, stems=stems
        )


# --------------------------------------------------------------------------
# 2.6 — dual output (eval stems vs scope stems)
# --------------------------------------------------------------------------


def _list_yaml_stems(datasets_dir: Path) -> list[str]:
    if not datasets_dir.is_dir():
        return []
    return sorted(path.stem for path in datasets_dir.glob("*.yaml"))


def partition_stems(
    *,
    changed_metric_stems: set[str],
    deleted_metric_stems: set[str],
    fanned_out_stems: set[str],
    fallback_to_all: bool,
    all_stems: list[str],
    metadata_only_stems: set[str] | None = None,
) -> tuple[list[str], list[str]]:
    """Return ``(eval_stems, scope_stems)``, both sorted.

    ``scope_stems`` is every stem whose doc changed (added/modified/renamed/
    deleted) or was fanned out to, including stems with no dataset file yet
    and deleted docs — Story 3 needs the deleted ones to prune stale
    auto-generated datasets. ``eval_stems`` is ``scope_stems`` minus deleted
    docs, intersected with stems that actually have a dataset file today.

    ``metadata_only_stems`` are dropped from ``eval_stems`` only — the cheap
    drift check stays broad while the expensive eval skips edits that cannot
    change what SQL is correct. A stem also reached by business-doc fan-out is
    still evaluated: that fan-out is evidence of a real semantic change
    elsewhere.
    """
    metadata_only = metadata_only_stems or set()
    existing_dataset_stems = set(all_stems)
    if fallback_to_all:
        scope = (
            set(all_stems)
            | changed_metric_stems
            | deleted_metric_stems
            | fanned_out_stems
        )
        eval_stems = set(all_stems) & existing_dataset_stems
        return sorted(eval_stems), sorted(scope)

    scope = changed_metric_stems | deleted_metric_stems | fanned_out_stems
    eval_candidates = (changed_metric_stems - metadata_only) | fanned_out_stems
    eval_stems = (eval_candidates - deleted_metric_stems) & existing_dataset_stems
    return sorted(eval_stems), sorted(scope)


# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class ScopeResult:
    eval_stems: list[str]
    scope_stems: list[str]
    fallback_triggered: bool
    fallback_reasons: list[str]
    metadata_only_stems: list[str] = field(default_factory=list)
    diff_range_warnings: list[str] = field(default_factory=list)


def resolve_scope(
    *,
    repo_root: Path,
    diff_range: DiffRange,
    datasets_dir: Path,
    parse_markdown: Callable[..., Any],
    max_samples: int,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> ScopeResult:
    """Full I/O orchestration: git diff -> classify -> resolve -> budget-check."""
    diff_range, range_warning = ensure_usable_diff_range(
        diff_range, cwd=repo_root, run=run
    )
    diff_range_warnings = [range_warning] if range_warning else []

    raw = run_git_diff(diff_range, cwd=repo_root, run=run)
    entries = parse_name_status_z(raw)
    classified = classify_paths(entries)

    changed_metric, deleted_metric = metric_stems_from_entries(
        classified.metric_entries
    )

    metadata_only = find_metadata_only_stems(
        classified.metric_entries,
        repo_root=repo_root,
        old_ref=resolve_old_ref(diff_range, cwd=repo_root, run=run),
        run=run,
    )

    fanned: set[str] = set()
    fallback_reasons: list[str] = []
    if classified.business_entries:
        metric_docs = load_metric_docs(
            repo_root / "docs" / "llm_context" / "metric_entities"
        )
        reverse_index = build_reverse_index(metric_docs, parse_markdown=parse_markdown)

        def _read_business_doc(entry: DiffEntry) -> str | None:
            if entry.status == "D":
                return None
            try:
                return (repo_root / entry.path).read_text(encoding="utf-8")
            except OSError:
                return None

        fanned, unresolved = fan_out(
            classified.business_entries,
            reverse_index=reverse_index,
            read_business_doc=_read_business_doc,
        )
        fallback_reasons = [
            f"business doc '{stem}' changed but has no resolvable related metric "
            "entities (neither the reverse index nor its own 'Related Metric "
            "Entities' section) — skipping eval/drift for this doc (merge allowed)"
            for stem in unresolved
        ]

    # Option 2: do not fail-closed to the full corpus. Unlinked business-entity
    # edits must not inherit unrelated stems' drift checks or LLM eval cost.
    fallback_triggered = False
    all_stems = _list_yaml_stems(datasets_dir)

    eval_stems, scope_stems = partition_stems(
        changed_metric_stems=changed_metric,
        deleted_metric_stems=deleted_metric,
        fanned_out_stems=fanned,
        fallback_to_all=fallback_triggered,
        all_stems=all_stems,
        metadata_only_stems=metadata_only,
    )

    total = total_sample_count(eval_stems, datasets_dir=datasets_dir)
    apply_budget(total, max_samples=max_samples, stems=eval_stems)

    return ScopeResult(
        eval_stems=eval_stems,
        scope_stems=scope_stems,
        fallback_triggered=fallback_triggered,
        fallback_reasons=fallback_reasons,
        metadata_only_stems=sorted(metadata_only),
        diff_range_warnings=diff_range_warnings,
    )


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base",
        default=None,
        help="Explicit diff base ref (overrides CI auto-detection)",
    )
    parser.add_argument(
        "--head", default=None, help="Explicit diff head ref (default: HEAD)"
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Override repo root used for git diff (default: auto-discovered)",
    )
    parser.add_argument(
        "--datasets-dir",
        type=Path,
        default=None,
        help="Override datasets/ dir (default: packages/tars-evals/datasets)",
    )
    parser.add_argument(
        "--max-samples",
        type=int,
        default=None,
        help="Sample budget guard (default: $TARS_EVAL_MAX_SAMPLES or 60)",
    )
    parser.add_argument(
        "--print",
        choices=("eval", "scope"),
        default="eval",
        dest="print_which",
        help="Which stem list to print to stdout, one per line (default: eval)",
    )
    parser.add_argument(
        "--write-eval-stems",
        type=Path,
        default=None,
        help="Also write eval stems (one per line) to this path",
    )
    parser.add_argument(
        "--write-scope-stems",
        type=Path,
        default=None,
        help="Also write scope stems (one per line) to this path",
    )
    args = parser.parse_args(argv)

    try:
        root = args.repo_root or repo_root()
    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    datasets_dir = args.datasets_dir or (root / "packages" / "tars-evals" / "datasets")
    max_samples = args.max_samples
    if max_samples is None:
        max_samples = int(
            os.environ.get("TARS_EVAL_MAX_SAMPLES", str(_DEFAULT_MAX_SAMPLES))
        )

    diff_range = resolve_diff_range(
        env=os.environ, explicit_base=args.base, explicit_head=args.head
    )

    try:
        doc_parser = load_document_parser()
    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    try:
        result = resolve_scope(
            repo_root=root,
            diff_range=diff_range,
            datasets_dir=datasets_dir,
            parse_markdown=doc_parser.parse_entity_markdown,
            max_samples=max_samples,
        )
    except (GitDiffError, DiffParseError, BudgetExceededError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    for warning in result.diff_range_warnings:
        print(f"WARN: {warning}", file=sys.stderr)
    for reason in result.fallback_reasons:
        print(f"WARN: {reason}", file=sys.stderr)

    if result.metadata_only_stems:
        print(
            "NOTE: not evaluating "
            f"{', '.join(result.metadata_only_stems)} — changed only in "
            f"eval-irrelevant section(s): {', '.join(sorted(_EVAL_IRRELEVANT_H2))}. "
            "Still drift-checked.",
            file=sys.stderr,
        )

    if args.write_eval_stems:
        args.write_eval_stems.write_text(
            "".join(f"{s}\n" for s in result.eval_stems), encoding="utf-8"
        )
    if args.write_scope_stems:
        args.write_scope_stems.write_text(
            "".join(f"{s}\n" for s in result.scope_stems), encoding="utf-8"
        )

    chosen = result.eval_stems if args.print_which == "eval" else result.scope_stems
    for stem in chosen:
        print(stem)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
