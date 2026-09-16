#!/usr/bin/env python3
"""Deterministic, offline gate for DataHub context entity ``.md`` files.

Validates ``docs/llm_context/{domain,metric}_entities/**`` on every PR, before they
reach ``master`` and the DataHub publish step. It reuses the SAME authoritative parser
and validator the publish path relies on
(:func:`sync.document_parser.parse_entity_markdown` +
:func:`sync.document_parser.validate_parsed_document`), so the CI gate and the publish
step can't disagree on the template contract. The ``data_product_type`` (metric vs
domain) is selected per file by its directory.

Intentionally free of any DataHub/LLM dependency (stdlib + the pure-``re`` ``sync``
package only): it must run on a plain ``uv run python`` with no ``DATAHUB_*`` /
``OPENAI_API_KEY`` credentials.

Usage:
    # CI: only the entity docs changed in this PR / push
    python validate_datahub_context_entities.py --changed-only -b "$CI_COMMIT_BRANCH"
    # Local: an explicit set of files, or every committed doc
    python validate_datahub_context_entities.py --paths docs/llm_context/metric_entities/turnover.md
    python validate_datahub_context_entities.py --all

Exit codes: 0 = all validated files pass (warnings do not fail); 1 = a blocking error
or a malformed invocation.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

# Ensure the sibling ``sync`` package is importable when run as a script from any
# cwd when run as a script from any working directory.
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

_REPO_ROOT = _SCRIPT_DIR.parents[
    2
]  # dags/governance/datahub_business_context → repo root

_DOMAIN_DIR = "docs/llm_context/domain_entities"
_METRIC_DIR = "docs/llm_context/metric_entities"

# Entity filenames are lowercase_snake_case (matches the on-disk slug the DataHub
# flow derives via ``product_id.replace("-", "_")`` and the template's rule).
_SNAKE_CASE_RE = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")

# Template placeholder tokens like ``{Official Metric Name}`` /
# ``{data_owner_email@quintoandar.com.br}``. Detected outside code fences so a
# legitimate SQL/JSON brace is never mistaken for a leftover stub.
_PLACEHOLDER_RE = re.compile(r"\{[A-Za-z][^{}\n]{1,80}\}")
_FENCED_CODE_RE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE_RE = re.compile(r"`[^`\n]+`")

# The template's writing-guide comment blocks are explicitly meant to be deleted
# before committing; leaving them in leaks guide prose into the DataHub Data
# Product description.
_WRITING_GUIDE_RE = re.compile(r"WRITING GUIDE", re.IGNORECASE)
_TBD_RE = re.compile(r"\bTBD\b", re.IGNORECASE)
_MARKDOWN_LINK_RE = re.compile(r"\[[^\]]*\]\([^)]*\)")
_URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)


def _resolve_diff_from_ref(branch: str) -> str:
    """Diff base for ``<from_ref>...HEAD``. Inlined (not imported from
    ``bietlejuice.ci.ci_diff_ref``) to keep this governance script dependency-free:
    a ``pull_request`` validates the full PR diff (``origin/master``); a push to a
    long-lived branch only its last commit (``HEAD~1``).
    """
    if os.environ.get("CI_PIPELINE_EVENT", "").strip() == "pull_request":
        return "origin/master"
    if branch in {"master", "forno"} or branch.startswith("hotfix/"):
        return "HEAD~1"
    return "origin/master"


_LEGACY_DOMAIN_DIR = "docs/llm_context/business_entities"

# Mechanical rename of the domain-entity concept. Applied when deciding whether
# a changed entity doc is "new authoring" vs the same document after the
# folder/heading/path/prose rename. Do not fold ``business_domain`` into this.
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


def _normalize_entity_rename_contract(text: str) -> str:
    """Collapse the business→domain rename so identical docs compare equal."""
    for old, new in _RENAME_CONTRACT_REPLACEMENTS:
        text = text.replace(old, new)
    return text


def _git_file_at_ref(from_ref: str, rel: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"{from_ref}:{rel}"],
        capture_output=True,
        text=True,
        cwd=_REPO_ROOT,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def _is_rename_contract_only(path: Path, from_ref: str) -> bool:
    """True when the working-tree doc matches the base after the rename mapping.

    Folder move + ``## Related Domain Entities`` + path/prose substitutions must
    not re-gate pre-existing template gaps that ``--changed-only`` never ran on
    master. A genuine authoring edit (new section, new file) returns False.
    """
    rel = _rel(path).as_posix()
    try:
        new = path.read_text(encoding="utf-8")
    except OSError:
        return False
    candidates = [rel]
    if rel.startswith(f"{_DOMAIN_DIR}/"):
        candidates.append(rel.replace(_DOMAIN_DIR, _LEGACY_DOMAIN_DIR, 1))
    old = None
    for candidate in candidates:
        old = _git_file_at_ref(from_ref, candidate)
        if old is not None:
            break
    if old is None:
        return False
    return _normalize_entity_rename_contract(old) == _normalize_entity_rename_contract(
        new
    )


def _git_changed_entity_files(branch: str) -> list[Path]:
    """Repo-relative entity ``.md`` paths added/modified vs the diff base."""
    from_ref = _resolve_diff_from_ref(branch)
    # --diff-filter=ACMR: added/copied/modified/renamed (never deleted files).
    cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{from_ref}...HEAD"]
    result = subprocess.run(
        cmd, capture_output=True, text=True, check=True, cwd=_REPO_ROOT
    )
    return [
        path
        for path in _filter_entity_paths(
            line.strip() for line in result.stdout.splitlines() if line.strip()
        )
        if not _is_rename_contract_only(path, from_ref)
    ]


def _all_entity_files() -> list[Path]:
    found: list[Path] = []
    for rel in (_DOMAIN_DIR, _METRIC_DIR):
        d = _REPO_ROOT / rel
        if d.is_dir():
            found.extend(p for p in d.glob("*.md") if not p.name.startswith("_"))
    return sorted(found, key=lambda p: str(p))


def _is_entity_md(path: Path) -> bool:
    """True for an entity ``.md`` under one of the two llm_context dirs (not ``_*``)."""
    parts = path.parts
    return (
        "llm_context" in parts
        and ("metric_entities" in parts or "domain_entities" in parts)
        and path.suffix == ".md"
        and not path.name.startswith("_")
    )


def _filter_entity_paths(paths) -> list[Path]:
    """Keep only entity ``.md`` under the two dirs, dropping ``_TEMPLATE`` etc.

    Accepts repo-relative strings/Paths (from git diff / glob) or absolute Paths
    (local ``--paths`` testing, possibly outside the repo).
    """
    out: list[Path] = []
    for p in paths:
        path = p if isinstance(p, Path) else Path(p)
        if not path.is_absolute():
            path = _REPO_ROOT / path
        if _is_entity_md(path):
            out.append(path)
    return sorted(set(out), key=str)


def _rel(path: Path) -> Path:
    """Repo-relative display path, or the path itself when it's outside the repo."""
    try:
        return path.relative_to(_REPO_ROOT)
    except ValueError:
        return path


def _data_product_type(path: Path) -> str:
    from sync.constants import DATA_PRODUCT_TYPE_DOMAIN, DATA_PRODUCT_TYPE_METRIC

    return (
        DATA_PRODUCT_TYPE_METRIC
        if "metric_entities" in path.parts
        else DATA_PRODUCT_TYPE_DOMAIN
    )


def _template_hint(path: Path) -> str:
    """Repo-relative authoring template for this doc's type (shown on failure)."""
    base = _METRIC_DIR if "metric_entities" in path.parts else _DOMAIN_DIR
    return f"{base}/_TEMPLATE.md"


def _strip_code(markdown: str) -> str:
    """Blank out fenced + inline code so brace/placeholder checks skip SQL."""
    markdown = _FENCED_CODE_RE.sub("", markdown)
    return _INLINE_CODE_RE.sub("", markdown)


def _strip_code_preserve_newlines(markdown: str) -> str:
    """Blank fenced blocks but keep line count for actionable TBD locations."""
    markdown = _FENCED_CODE_RE.sub(
        lambda match: "\n" * match.group(0).count("\n"), markdown
    )
    return _INLINE_CODE_RE.sub("", markdown)


def _strip_urls_and_links(markdown: str) -> str:
    markdown = _MARKDOWN_LINK_RE.sub("", markdown)
    return _URL_RE.sub("", markdown)


def _find_tbd_snippets(markdown: str, *, limit: int = 5) -> list[str]:
    scanned = _strip_urls_and_links(_strip_code_preserve_newlines(markdown))
    snippets: list[str] = []
    for line_no, line in enumerate(scanned.splitlines(), start=1):
        if _TBD_RE.search(line):
            snippet = line.strip()
            if len(snippet) > 120:
                snippet = snippet[:117] + "..."
            snippets.append(f"line {line_no}: {snippet}")
            if len(snippets) >= limit:
                break
    return snippets


def _static_checks(path: Path, content: str) -> tuple[list[str], list[str]]:
    """Static template-contract checks the parser doesn't cover; returns (errors, warnings).

    Conservative by design: filename casing is only a warning (hyphen/underscore map
    to the same DataHub product_id), and only the template's ``WRITING GUIDE`` block —
    not any HTML comment — is a blocking leftover.
    """
    errors: list[str] = []
    warnings: list[str] = []

    if not _SNAKE_CASE_RE.match(path.stem):
        warnings.append(
            f"Filename '{path.name}' is not lowercase_snake_case "
            "(the template recommends e.g. nps_fr.md, gmv_fs.md)."
        )

    if _WRITING_GUIDE_RE.search(content):
        errors.append(
            "The template's 'WRITING GUIDE' comment block is still present — "
            "delete it before committing (it would leak into the DataHub "
            "description)."
        )

    placeholders = sorted(set(_PLACEHOLDER_RE.findall(_strip_code(content))))
    if placeholders:
        shown = ", ".join(placeholders[:5])
        errors.append(f"Unfilled template placeholder(s) left in the document: {shown}")

    tbd_snippets = _find_tbd_snippets(content)
    if tbd_snippets:
        errors.append(
            "Unresolved 'TBD' placeholder left in the document: "
            + "; ".join(tbd_snippets)
        )

    return errors, warnings


def _validate_file(path: Path) -> tuple[list[str], list[str]]:
    """Return (errors, warnings) for a single entity ``.md``."""
    from sync.document_parser import parse_entity_markdown, validate_parsed_document
    from sync.markdown_sanitizer import sanitize_uploaded_markdown

    try:
        content = path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"could not read file: {exc}"], []

    errors, warnings = _static_checks(path, content)

    # No fallback_title: a committed entity doc MUST carry its own ``# H1`` title
    # (the template mandates it), so a missing H1 surfaces as a blocking error
    # instead of being silently filled from the filename.
    parsed = parse_entity_markdown(
        content,
        unescape=False,
        sanitize_fn=sanitize_uploaded_markdown,
    )
    struct_errors, struct_warnings = validate_parsed_document(
        parsed, data_product_type=_data_product_type(path)
    )
    errors.extend(struct_errors)
    warnings.extend(struct_warnings)
    errors.extend(_domain_allowlist_errors(parsed.domain))
    return errors, warnings


def _domain_allowlist_errors(domain: str) -> list[str]:
    """Blocking error when ``## Domain`` is outside the metadata domain allowlist.

    Lives here rather than in the parser because it needs the registry, and the parser
    is kept stdlib-only so tars-evals can load it by file path. Reading the allowlist
    from ``domain_registry`` instead of restating it keeps this from becoming a second
    copy that drifts: the value is written verbatim into the metric metadata the
    generator phase produces, where Yamale and the FAIR gate accept nothing else.
    """
    if not (domain or "").strip():
        return []  # absence is already reported by validate_parsed_document
    try:
        from bietlejuice.governance.domain_registry import active_domains
    except ImportError:  # pragma: no cover - bietlejuice-core is installed in CI
        return []
    allowed = active_domains()
    if domain in allowed:
        return []
    return [
        f"## Domain is {domain!r}, which is not in the metadata domain allowlist "
        f"({', '.join(allowed)})"
    ]


def _pr_comment_body(failures: list[tuple[str, str, list[str]]]) -> str:
    """User-facing markdown listing each failing doc and its blocking errors."""
    lines = [
        "❌ The automated check found issues in your Data Product documentation. "
        "Please fix them and re-upload the `.md`:",
        "",
    ]
    for rel, dp_type, errors in failures:
        lines.append(f"**{rel}** ({dp_type})")
        lines.extend(f"- {e}" for e in errors)
        lines.append("")
    return "\n".join(lines).rstrip()


# Only Luigi self-service PRs (branch ``luigi/data-product/<slug>``) get the bot
# comment — the whole point is the non-technical submitter who doesn't watch CI; a
# regular engineer editing an entity doc watches Woodpecker themselves.
_LUIGI_BRANCH_PREFIX = "luigi/data-product/"


def _luigi_pr_number() -> str:
    """The PR number when this run is a Luigi self-service submission (its branch is
    ``luigi/data-product/*``), else ``""`` — used to gate the bot comment."""
    pr_number = os.environ.get("CI_COMMIT_PULL_REQUEST", "").strip()
    branch = (
        os.environ.get("CI_COMMIT_SOURCE_BRANCH")
        or os.environ.get("CI_COMMIT_BRANCH")
        or ""
    ).strip()
    return pr_number if pr_number and branch.startswith(_LUIGI_BRANCH_PREFIX) else ""


def _maybe_comment_on_pr(failures: list[tuple[str, str, list[str]]]) -> None:
    """On a Luigi PR, post the failures as a comment for the submitter. Best-effort — a
    non-Luigi PR, a missing token / PR number, or an API error never changes the exit
    code."""
    pr_number = _luigi_pr_number()
    if not pr_number or not failures:
        return
    try:
        from sync.pr_comment import post_validation_failure

        post_validation_failure(pr_number, _pr_comment_body(failures))
    except Exception:  # pragma: no cover - defensive; posting must never break CI
        pass


def _maybe_comment_success() -> None:
    """On a Luigi PR, post the success comment on every pass — so the submitter always
    learns the automated review is green and only the manual review remains. Best-effort;
    idempotent (an unchanged comment isn't rewritten)."""
    pr_number = _luigi_pr_number()
    if not pr_number:
        return
    try:
        from sync.pr_comment import post_validation_success

        post_validation_success(pr_number)
    except Exception:  # pragma: no cover - defensive; posting must never break CI
        pass


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate DataHub context entity .md files (domain + metric) "
            "against the authoring template contract."
        )
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--changed-only",
        action="store_true",
        help="Validate only entity docs changed vs the diff base (CI).",
    )
    group.add_argument(
        "--all",
        action="store_true",
        help="Validate every committed entity doc (local audit).",
    )
    group.add_argument(
        "--paths",
        nargs="+",
        type=Path,
        help="Explicit .md paths to validate (local testing).",
    )
    parser.add_argument(
        "-b",
        "--branch",
        default=os.environ.get("CI_COMMIT_BRANCH", ""),
        help="Current branch (CI_COMMIT_BRANCH); used with --changed-only.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)

    if args.paths:
        files = _filter_entity_paths(args.paths)
        # Explicit paths that fall outside the entity dirs are a user error.
        if not files:
            print(
                "✗ none of the given --paths are entity .md files under "
                f"{_DOMAIN_DIR}/ or {_METRIC_DIR}/",
                file=sys.stderr,
            )
            return 1
        print(f"Scope           : {len(files)} explicitly-listed entity doc(s)")
    elif args.all:
        files = _all_entity_files()
        print(f"Scope           : every committed entity doc ({len(files)})")
    else:  # --changed-only
        from_ref = _resolve_diff_from_ref(args.branch)
        # Scope is the whole branch delta (<base>...HEAD), not just the last commit,
        # so a doc changed by an earlier commit on the branch is validated too.
        print(
            f"Scope           : entity docs changed vs {from_ref} "
            f"({from_ref}...HEAD — whole branch delta, not just the last commit)"
        )
        try:
            files = _git_changed_entity_files(args.branch)
        except subprocess.CalledProcessError as exc:
            print(f"✗ git diff failed: {exc}", file=sys.stderr)
            return 1
        if not files:
            print("No changed entity docs detected — nothing to validate.")
            return 0

    print(f"Validating {len(files)} entity doc(s)…")
    n_failed = 0
    n_warnings = 0
    failures: list[tuple[str, str, list[str]]] = []  # (rel_path, dp_type, errors)
    for path in files:
        rel = _rel(path)
        # The contract enforced differs by type (metric vs domain); surface which
        # one was applied so a passing/failing line is unambiguous.
        dp_type = _data_product_type(path)
        errors, warnings = _validate_file(path)
        n_warnings += len(warnings)
        for w in warnings:
            print(f"  ⚠ {rel}: {w}")
        if errors:
            n_failed += 1
            failures.append((str(rel), dp_type, errors))
            print(f"  ✗ {rel} ({dp_type}, {len(errors)} error(s)):", file=sys.stderr)
            for e in errors:
                print(f"      • {e}", file=sys.stderr)
            print(f"      → see the template: {_template_hint(path)}", file=sys.stderr)
        else:
            print(f"  ✓ {rel} ({dp_type})")

    if n_warnings:
        print(f"\n{n_warnings} warning(s) — non-blocking (they do not fail the build).")

    if n_failed:
        # Surface the failure ON the PR (best-effort) so the non-technical Luigi
        # submitter, who doesn't watch Woodpecker, gets the reason relayed to Chat by
        # zordon's poller. Only on a pull_request with a token; never affects exit code.
        _maybe_comment_on_pr(failures)
        print(
            f"\n✗ {n_failed} entity doc(s) failed validation. Fix the errors above "
            "and push again.",
            file=sys.stderr,
        )
        return 1
    print("\n✓ All entity docs pass validation.")
    _maybe_comment_success()
    return 0


if __name__ == "__main__":
    sys.exit(main())
