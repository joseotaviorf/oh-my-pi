#!/usr/bin/env python3
"""Block Databricks-specific SQL constructs in new/changed .sql files.

Scans every SQL file that appears in the current git diff (new or modified) and
fails if any Databricks-only syntax is found.  Existing, unmodified files are
never inspected.

Usage (CI — branch resolved via CI_COMMIT_BRANCH):
    python validate_databricks_sql_constructs.py -b "$CI_COMMIT_BRANCH"

Usage (local):
    python validate_databricks_sql_constructs.py -b "$(git branch --show-current)"

Usage (scan every .sql file under dags/):
    python validate_databricks_sql_constructs.py -a
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple

sys.path.append(str(Path(__file__).parent.parent))
from services.git_service import GitService

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref

# ---------------------------------------------------------------------------
# Constructs that are Databricks-only and break on EMR Spark 3.5
# Each entry: (display_name, compiled_regex)
# ---------------------------------------------------------------------------
_CONSTRUCTS = [
    (
        "QUALIFY",
        re.compile(r"\bQUALIFY\b", re.IGNORECASE),
    ),
    (
        "IFF()",
        re.compile(r"\bIFF\s*\(", re.IGNORECASE),
    ),
    (
        "DATEDIFF with unit (3-arg form)",
        re.compile(
            r"\bDATEDIFF\s*\(\s*'?"
            r"(YEAR|QUARTER|MONTH|WEEK|DAY|HOUR|MINUTE|SECOND|MILLISECOND|MICROSECOND)'?",
            re.IGNORECASE,
        ),
    ),
    (
        "Variant accessor (column:key)",
        # Two forms after string literals are stripped:
        #   col:field   → \w+:(?!:)\w  (bare identifier accessor)
        #   col:["key"] → \w+:\[       (bracket accessor; string content already removed)
        # The (?!:) prevents matching :: (PostgreSQL cast, handled separately).
        re.compile(r"\w+:(?!:)(?:\w|\[)", re.IGNORECASE),
    ),
    (
        "PostgreSQL :: cast",
        re.compile(r"::[A-Za-z]"),
    ),
    (
        "SELECT * EXCEPT (...)",
        re.compile(r"\bSELECT\s+\*\s+EXCEPT\s*\(", re.IGNORECASE),
    ),
]

_COMMENT_RE = re.compile(r"--.*$")
# Matches single- and double-quoted string literals (handles \' and \" escapes).
# Used to blank out string contents before pattern matching so that colons inside
# format strings like 'HH:mm:ss' or "yyyy-MM-dd HH:mm:ss" don't trip the variant
# accessor rule.
_STRING_LITERAL_RE = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")


class Violation(NamedTuple):
    filepath: str
    line_no: int
    construct: str
    text: str


def _strip_line_comment(line: str) -> str:
    return _COMMENT_RE.sub("", line)


def _strip_string_literals(line: str) -> str:
    return _STRING_LITERAL_RE.sub("''", line)


def scan_file(path: Path) -> List[Violation]:
    violations: List[Violation] = []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        print(f"WARNING: cannot read {path}: {exc}", file=sys.stderr)
        return violations

    for line_no, raw_line in enumerate(lines, start=1):
        stripped = _strip_string_literals(_strip_line_comment(raw_line))
        for construct, pattern in _CONSTRUCTS:
            if pattern.search(stripped):
                violations.append(
                    Violation(
                        filepath=str(path),
                        line_no=line_no,
                        construct=construct,
                        text=raw_line.strip(),
                    )
                )
                break  # one violation per line is enough
    return violations


def get_changed_sql_files(branch: str) -> List[Path]:
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    diff: Dict[str, str] = git_service.get_modified_files_from_diff(from_ref, "HEAD")
    return [
        Path(filepath)
        for filepath, status in diff.items()
        if filepath.endswith(".sql") and status in git_service.UPSERT_STATUS_CODES
    ]


def get_all_sql_files() -> List[Path]:
    return list(Path("dags").rglob("*.sql"))


def parse_args():
    parser = argparse.ArgumentParser(
        description="Fail if changed SQL files contain Databricks-only constructs."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", help="Current branch (CI_COMMIT_BRANCH)")
    group.add_argument(
        "-a",
        "--all-files",
        action="store_true",
        help="Scan all .sql files under dags/ (local audit)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.all_files:
        sql_files = get_all_sql_files()
        print(f"Scanning all {len(sql_files)} SQL files under dags/")
    else:
        sql_files = get_changed_sql_files(args.branch)
        if not sql_files:
            print("No changed SQL files detected — nothing to validate.")
            return 0
        print(f"Scanning {len(sql_files)} changed SQL file(s)")

    all_violations: List[Violation] = []
    for path in sql_files:
        if path.exists():
            all_violations.extend(scan_file(path))

    if not all_violations:
        print("OK: No Databricks-specific constructs found.")
        return 0

    print(
        f"\n❌  Found {len(all_violations)} Databricks-only construct(s) "
        "that are incompatible with EMR Spark 3.5:\n",
        file=sys.stderr,
    )
    for v in all_violations:
        print(
            f"  {v.filepath}:{v.line_no}: [{v.construct}]\n      {v.text}",
            file=sys.stderr,
        )
    print(
        "\nRewrite these constructs to standard Spark SQL before merging. "
        "See .cursor/skills/databricks-emr-migration/ for rewrite recipes.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
