"""Human-readable CI report formatting for PII privacy validation."""

from __future__ import annotations

import re
from typing import Iterable, Optional, Sequence

_BANNER_WIDTH = 80

_PENDING_UPSTREAM = re.compile(
    r"^(?P<file>.+?) column '(?P<column>[^']+)': pending_upstream "
    r"\((?P<upstream>[^)]+) has no privacy classification yet\)$"
)
_DIVERGES = re.compile(
    r"^(?P<file>.+?) column '(?P<column>[^']+)': piiType "
    r"'(?P<down>[^']+)' diverges from upstream '(?P<up>[^']+)' "
    r"piiType '(?P<up_pii>[^']+)'$"
)
_LINEAGE_SKIP = re.compile(
    r"^(?P<file>.+?) column '(?P<column>[^']+)': lineage '(?P<ref>[^']+)' "
    r"is out of repo scope \(skipped\)$"
)
_INVALID_LINEAGE = re.compile(
    r"^(?P<file>.+?) column '(?P<column>[^']+)': invalid lineage ref "
    r"'(?P<ref>[^']+)': (?P<detail>.+)$"
)
_JSONPATHS_UNVALIDATED = re.compile(
    r"^(?P<file>.+?) column '(?P<column>[^']+)': jsonPaths lineage is not "
    r"validated yet$"
)
_TABLE_SUBJECT = re.compile(
    r"^(?P<file>.+?): table privacy\.dataSubjectType (?P<down>.+) is "
    r"incompatible with upstream table (?P<table>[^ ]+) (?P<up>.+)$"
)


def relative_repo_path(path: str) -> str:
    """Strip CI absolute prefixes; keep paths rooted at dags/ or governance/."""
    normalized = path.replace("\\", "/")
    for anchor in ("dags/", "governance/"):
        idx = normalized.find(anchor)
        if idx >= 0:
            return normalized[idx:]
    return normalized


def humanize_warning(message: str) -> str:
    """Turn validator warnings into short, actionable CI text."""
    rel = relative_repo_path(message)
    if match := _PENDING_UPSTREAM.match(rel):
        return (
            f"  • {match.group('file')} · column `{match.group('column')}`\n"
            f"    Upstream `{match.group('upstream')}` has no privacy metadata yet.\n"
            f"    → Classify upstream in a prior PR or document an exception in RAE."
        )
    if match := _DIVERGES.match(rel):
        return (
            f"  • {match.group('file')} · column `{match.group('column')}`\n"
            f"    piiType `{match.group('down')}` differs from upstream "
            f"`{match.group('up')}` (`{match.group('up_pii')}`).\n"
            f"    → Align piiType with upstream or fix lineage."
        )
    if match := _LINEAGE_SKIP.match(rel):
        return (
            f"  • {match.group('file')} · column `{match.group('column')}`\n"
            f"    Lineage `{match.group('ref')}` is outside this repo (skipped)."
        )
    if match := _INVALID_LINEAGE.match(rel):
        return (
            f"  • {match.group('file')} · column `{match.group('column')}`\n"
            f"    Invalid lineage `{match.group('ref')}`: {match.group('detail')}"
        )
    if match := _JSONPATHS_UNVALIDATED.match(rel):
        return (
            f"  • {match.group('file')} · column `{match.group('column')}`\n"
            "    This column is classified only via `privacy.jsonPaths`.\n"
            "    → Lineage checks do not validate per-path piiType yet."
        )
    if match := _TABLE_SUBJECT.match(rel):
        return (
            f"  • {match.group('file')}\n"
            f"    Table titular {match.group('down')} conflicts with upstream "
            f"`{match.group('table')}` ({match.group('up')}).\n"
            f"    → Fix privacy.dataSubjectType or upstream lineage."
        )
    return f"  • {rel}"


def humanize_error(message: str) -> str:
    rel = relative_repo_path(message)
    if ": " in rel and not rel.startswith("  •"):
        file_part, _, detail = rel.partition(": ")
        return f"  • {file_part}\n    {detail}"
    return f"  • {rel}"


def _banner(title: str) -> None:
    print("\n" + "=" * _BANNER_WIDTH)
    print(title)
    print("=" * _BANNER_WIDTH + "\n")


def print_scope_header(
    *,
    branch: Optional[str],
    domain: Optional[str],
    file_count: int,
) -> None:
    _banner("PII PRIVACY VALIDATION")
    if branch:
        print(f"Branch: {branch}")
    if domain:
        print(f"Domain: {domain}")
    print(f"Metadata files in scope: {file_count}\n")


def print_no_files_in_scope(*, domain: Optional[str]) -> None:
    if domain:
        print(f"No metadata changes in this PR for domain `{domain}`.\n")
    else:
        print("No metadata files in scope for this run.\n")


def print_report(
    *,
    passed: Sequence[str],
    skipped: Sequence[str],
    warnings: Iterable[str],
    errors: Iterable[str],
    tier_notes: Sequence[str],
    verbose: bool,
) -> None:
    passed_rel = [relative_repo_path(p) for p in passed]
    skipped_rel = [relative_repo_path(p) for p in skipped]

    if passed_rel:
        print(f"✅ PASSED ({len(passed_rel)} file(s))")
        for path in passed_rel:
            print(f"  • {path}")
        print()

    if skipped_rel:
        print(f"⊘ SKIPPED ({len(skipped_rel)} file(s) — out of validation pattern)")
        for path in skipped_rel:
            print(f"  • {path}")
        print()

    warning_list = list(warnings)
    if warning_list:
        print(f"ℹ️  WARNINGS ({len(warning_list)}) — informational; does not fail CI\n")
        for warn in warning_list:
            print(humanize_warning(warn))
            print()

    error_list = list(errors)
    if error_list:
        print(f"❌ ERRORS ({len(error_list)}) — fix before merge\n")
        for err in error_list:
            print(humanize_error(err))
            print()

    if verbose and tier_notes:
        print("Catalog tiers (verbose):\n")
        for note in tier_notes:
            print(f"  • {relative_repo_path(note)}")
        print()

    if error_list:
        print("Result: PII privacy validation failed.\n")
    else:
        print("Result: PII privacy validation passed. ✅\n")


def format_tier_note(file_path: str, id_entity: str, pii_type: str, tier: str) -> str:
    return (
        f"{relative_repo_path(file_path)} {id_entity}: "
        f"piiType={pii_type} → catalog={tier}"
    )
