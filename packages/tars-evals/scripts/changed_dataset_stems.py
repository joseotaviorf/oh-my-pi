#!/usr/bin/env python3
"""Resolve which tars-evals dataset stems a git diff affects.

Stdlib-only so CI can call this before ``uv sync``. Diff-base resolution
mirrors ``bietlejuice.ci.ci_diff_ref`` but is reimplemented here because this
standalone package cannot depend on the workspace.

Two changed-doc directories are tracked:

- ``docs/llm_context/metric_entities/<stem>.md`` maps 1:1 to a dataset stem.
- ``docs/llm_context/domain_entities/<stem>.md`` fans out to related metric
  stems via a reverse index over metric docs' ``## Related Domain Entities``.
  Metric docs declare the relationship upward and CI inverts it; that is the
  only direction. A domain doc that matches no index key simply has no metric
  doc pointing at it — the normal state for most domain docs — so it resolves
  to zero stems and never fans out to every dataset stem in the repo.

A metric doc citing a domain entity that no doc answers to is warned about on
the PR that introduces it (see ``find_dangling_domain_references``), which is
the only place the typo can be fixed.

Two stem lists are emitted:

- **eval stems** — in-scope stems that have a dataset file today.
- **scope stems** — every in-scope stem, including docs with no dataset yet
  and deleted docs (used to prune stale auto-generated datasets).

A metric doc modified *only* inside an eval-irrelevant H2 section (see
``_EVAL_IRRELEVANT_H2``) is dropped from the **eval** list but kept in the
**scope** list: a Data Steward email edit cannot change what SQL is correct,
so it must not cost a ~4-minute, ~1.7M-token re-evaluation nor block the PR on
an LLM judge's opinion of SQL the author never touched. The same skip applies
to the mechanical business→domain **contract rename** (folder, ``## Related
Domain Entities`` heading, path/prose substitutions): that cannot change SQL
either, so it must not fan-out every domain doc into the sample budget.
The drift check is cheap and stays broad. The filter only ever shrinks the
scope on positive evidence — additions, deletions and unreadable blobs still
evaluate. A rename still evaluates when the blobs differ after the contract
mapping (real authoring on the moved file).

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
from collections.abc import Callable, Collection, Iterable, Mapping
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
_BUSINESS_PREFIX = "docs/llm_context/domain_entities/"
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
    """Partition diff entries into metric_entities / domain_entities changes.

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
# 2.4 — domain-entity fan-out
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
    """Pure: invert every metric doc's ``## Related Domain Entities`` field.

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

# Same mapping as ``validate_datahub_context_entities._RENAME_CONTRACT_REPLACEMENTS``.
# Duplicated here because this script is stdlib-only and must not import dags/.
# Do not fold ``business_domain`` into this list.
_RENAME_CONTRACT_REPLACEMENTS = (
    ("docs/llm_context/business_entities/", "docs/llm_context/domain_entities/"),
    ("## Related Business Entities", "## Related Domain Entities"),
    ("business_entities/", "domain_entities/"),
    ("Business Entities", "Domain Entities"),
    ("business entities", "domain entities"),
    ("Business Entity", "Domain Entity"),
    ("business entity", "domain entity"),
    ("business-entity", "domain-entity"),
    ("business_entity", "domain_entity"),
)


def normalize_entity_rename_contract(text: str) -> str:
    """Collapse the business→domain rename so identical docs compare equal."""
    # ``git show`` returns decoded bytes while ``Path.read_text`` applies
    # universal-newline translation. Normalize explicitly so a CRLF source
    # file moved unchanged is not mistaken for semantic authoring.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    for old, new in _RENAME_CONTRACT_REPLACEMENTS:
        text = text.replace(old, new)
    return text


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


def is_eval_irrelevant_change(old_text: str, new_text: str) -> bool:
    """True when the delta cannot change what SQL is correct.

    Applies the business→domain contract mapping first, then the ownership/
    changelog filter, so a heading/path rename (optionally plus a steward
    email edit) does not enqueue LLM evals.
    """
    return is_metadata_only_change(
        normalize_entity_rename_contract(old_text),
        normalize_entity_rename_contract(new_text),
    )


def is_contract_rename_only(old_text: str, new_text: str) -> bool:
    """True when normalizing business→domain is the complete content delta."""
    return normalize_entity_rename_contract(
        old_text
    ) == normalize_entity_rename_contract(new_text)


def _old_blob_path(entry: DiffEntry) -> str:
    if entry.status in {"R", "C"} and entry.old_path:
        return entry.old_path
    return entry.path


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
    """Stems whose modification cannot change what SQL is correct.

    Plain modifications (``M``) and folder/path renames (``R``) are considered
    when the old blob is readable. Additions, deletions and unreadable blobs
    fall through to evaluating — the filter may only ever *shrink* the scope
    on positive evidence.
    """
    metadata_only: set[str] = set()
    for entry in entries:
        if entry.status == "M":
            pass
        elif (
            entry.status == "R"
            and Path(_old_blob_path(entry)).stem == Path(entry.path).stem
        ):
            pass
        else:
            continue
        old_text = read_blob_at(old_ref, _old_blob_path(entry), cwd=repo_root, run=run)
        if old_text is None:
            continue
        try:
            new_text = (repo_root / entry.path).read_text(encoding="utf-8")
        except OSError:
            continue
        if is_eval_irrelevant_change(old_text, new_text):
            metadata_only.add(Path(entry.path).stem)
    return metadata_only


def find_contract_rename_only_stems(
    entries: Iterable[DiffEntry],
    *,
    repo_root: Path,
    old_ref: str | None,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> set[str]:
    """Metric stems whose complete delta is the mechanical contract rename."""
    contract_only: set[str] = set()
    for entry in entries:
        if entry.status == "M":
            pass
        elif (
            entry.status == "R"
            and Path(_old_blob_path(entry)).stem == Path(entry.path).stem
        ):
            pass
        else:
            continue
        old_text = read_blob_at(old_ref, _old_blob_path(entry), cwd=repo_root, run=run)
        if old_text is None:
            continue
        try:
            new_text = (repo_root / entry.path).read_text(encoding="utf-8")
        except OSError:
            continue
        if is_contract_rename_only(old_text, new_text):
            contract_only.add(Path(entry.path).stem)
    return contract_only


def entry_is_contract_rename_only(
    entry: DiffEntry,
    *,
    repo_root: Path,
    old_ref: str | None,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> bool:
    """True when a domain/metric diff entry is only the contract rename.

    A rename that changes the file stem (``metric_a.md`` → ``metric_a_renamed.md``)
    is a new eval identity and must still evaluate.
    """
    if entry.status == "M":
        pass
    elif (
        entry.status == "R"
        and Path(_old_blob_path(entry)).stem == Path(entry.path).stem
    ):
        pass
    else:
        return False
    old_text = read_blob_at(old_ref, _old_blob_path(entry), cwd=repo_root, run=run)
    if old_text is None:
        return False
    try:
        new_text = (repo_root / entry.path).read_text(encoding="utf-8")
    except OSError:
        return False
    return is_contract_rename_only(old_text, new_text)


_H1_RE = re.compile(r"^#\s+(.+)$", re.MULTILINE)


def business_display_name(markdown: str) -> str | None:
    """A business doc's declared H1 title, or ``None`` when it has no H1.

    This is the name metric docs cite in their ``## Related Domain Entities``
    bullets, and it does not always equal the filename — e.g.
    ``finance_revenue_cost.md`` is titled "Finance Revenue and Cost", so
    matching on the stem alone would miss the five metric docs that cite it.
    """
    match = _H1_RE.search(markdown)
    return match.group(1).strip() if match else None


def business_kebab_id(name: str) -> str:
    """Display name -> kebab business id, mirroring ``document_parser``'s
    ``_display_name_to_product_id`` — the id a metric doc's bullet produces
    (``House and Listing`` / ``house_and_listing`` -> ``house-and-listing``).

    Non-ASCII letters collapse to ``-`` (``Consórcio`` -> ``cons-rcio``). That
    is lossy but *identical* on both sides, since the metric doc's bullet goes
    through the same slugifier, so accented names still match each other.
    """
    return re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")


def fan_out(
    business_entries: Iterable[DiffEntry],
    *,
    reverse_index: Mapping[str, set[str]],
    read_business_doc: Callable[[DiffEntry], str | None],
) -> set[str]:
    """Resolve changed business docs to the metric stems that depend on them.

    The reverse index is the only source of the relationship: metric docs
    declare it upward in ``## Related Domain Entities`` and CI inverts it.
    A doc that matches no index key has no metric doc pointing at it, which is
    the normal state for most domain docs (there are far more domain docs than
    metric docs), so it resolves to zero stems without a warning. The typo case
    — a metric doc naming a domain entity nobody answers to — is caught on the
    metric side by ``find_dangling_domain_references``.

    Lookup is by the display name the doc declares in its H1, because that is
    the name metric docs cite; the file stem is tried too, for docs whose title
    and filename agree and for deleted docs, which can't be read.
    ``read_business_doc`` returns the doc's current markdown, or ``None`` when
    it can't be read.
    """
    fanned: set[str] = set()
    for entry in business_entries:
        text = read_business_doc(entry)
        lookup_names = [Path(entry.path).stem]
        if entry.old_path:
            lookup_names.append(Path(entry.old_path).stem)
        title = business_display_name(text) if text else None
        if title:
            lookup_names.append(title)
        for name in lookup_names:
            fanned |= set(reverse_index.get(business_kebab_id(name), ()))
    return fanned


def load_business_ids(domain_entities_dir: Path) -> set[str]:
    """I/O: every business id the domain docs on disk answer to (title + stem)."""
    ids: set[str] = set()
    if not domain_entities_dir.is_dir():
        return ids
    for md in sorted(domain_entities_dir.glob("*.md")):
        if md.name == _TEMPLATE_NAME:
            continue
        ids.add(business_kebab_id(md.stem))
        try:
            title = business_display_name(md.read_text(encoding="utf-8"))
        except OSError:
            title = None
        if title:
            ids.add(business_kebab_id(title))
    return ids


def find_dangling_domain_references(
    changed_metric_stems: Iterable[str],
    *,
    reverse_index: Mapping[str, set[str]],
    known_business_ids: Collection[str],
) -> list[tuple[str, list[str]]]:
    """Business ids cited by a changed metric doc that no domain doc answers to.

    Returns ``[(business_id, [citing_metric_stem, ...]), ...]``, surfaced as a
    warning on the PR that introduces the bad bullet — the only place it can be
    fixed. Scoped to *changed* metric docs so a pre-existing bad bullet
    elsewhere doesn't warn on every unrelated PR.
    """
    changed = set(changed_metric_stems)
    return sorted(
        (business_id, sorted(stems & changed))
        for business_id, stems in reverse_index.items()
        if business_id not in known_business_ids and stems & changed
    )


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
    scope_warnings: list[str]
    metadata_only_stems: list[str] = field(default_factory=list)
    contract_rename_only_stems: list[str] = field(default_factory=list)
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

    old_ref = resolve_old_ref(diff_range, cwd=repo_root, run=run)
    contract_only = find_contract_rename_only_stems(
        classified.metric_entries,
        repo_root=repo_root,
        old_ref=old_ref,
        run=run,
    )
    metadata_only = (
        find_metadata_only_stems(
            classified.metric_entries,
            repo_root=repo_root,
            old_ref=old_ref,
            run=run,
        )
        - contract_only
    )
    changed_metric -= contract_only

    fanned: set[str] = set()
    scope_warnings: list[str] = []
    business_for_fanout = tuple(
        entry
        for entry in classified.business_entries
        if not entry_is_contract_rename_only(
            entry, repo_root=repo_root, old_ref=old_ref, run=run
        )
    )
    llm_context = repo_root / "docs" / "llm_context"
    reverse_index: dict[str, set[str]] = {}
    if business_for_fanout or changed_metric:
        metric_docs = load_metric_docs(llm_context / "metric_entities")
        reverse_index = build_reverse_index(metric_docs, parse_markdown=parse_markdown)

    if business_for_fanout:

        def _read_business_doc(entry: DiffEntry) -> str | None:
            if entry.status == "D":
                return None
            try:
                return (repo_root / entry.path).read_text(encoding="utf-8")
            except OSError:
                return None

        fanned = fan_out(
            business_for_fanout,
            reverse_index=reverse_index,
            read_business_doc=_read_business_doc,
        )

    if changed_metric:
        scope_warnings = [
            f"metric doc(s) {', '.join(stems)} cite domain entity "
            f"'{business_id}', which matches no doc in "
            "docs/llm_context/domain_entities/ — fix the '## Related Domain "
            "Entities' bullet to match the target doc's title (merge allowed)"
            for business_id, stems in find_dangling_domain_references(
                changed_metric,
                reverse_index=reverse_index,
                known_business_ids=load_business_ids(llm_context / "domain_entities"),
            )
        ]

    # Option 2: do not fail-closed to the full corpus. Unlinked domain-entity
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
        scope_warnings=scope_warnings,
        metadata_only_stems=sorted(metadata_only),
        contract_rename_only_stems=sorted(contract_only),
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
    for warning in result.scope_warnings:
        print(f"WARN: {warning}", file=sys.stderr)

    if result.metadata_only_stems:
        print(
            "NOTE: not evaluating "
            f"{', '.join(result.metadata_only_stems)} — changed only in "
            f"eval-irrelevant ownership/changelog sections. Still drift-checked.",
            file=sys.stderr,
        )
    if result.contract_rename_only_stems:
        print(
            "NOTE: excluding "
            f"{', '.join(result.contract_rename_only_stems)} from eval and drift "
            "scope — changed only by the business→domain contract rename.",
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
