#!/usr/bin/env python3
"""Block Databricks-only SQL constructs and Spark-rejected trailing commas.

Scans every SQL file that appears in the current git diff (new or modified) and
fails if Databricks-only syntax is found, or if a SELECT list ends with a comma
immediately before FROM / WHERE / GROUP BY / etc. (Spark ParseException; PR
#27712). Existing, unmodified files are never inspected in branch mode.

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
_LINE_COMMENT_RE = re.compile(r"--[^\n]*")
_BLOCK_COMMENT_RE = re.compile(r"/\*(?!\+).*?\*/", re.DOTALL)
# Matches single- and double-quoted string literals (handles \' and \" escapes).
# Used to blank out string contents before pattern matching so that colons inside
# format strings like 'HH:mm:ss' or "yyyy-MM-dd HH:mm:ss" don't trip the variant
# accessor rule. DOTALL so a comma + FROM inside a multiline string is ignored.
_STRING_LITERAL_RE = re.compile(
    r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"",
    re.DOTALL,
)

# Spark / Trino reject a comma as the last SELECT-list item. SQLGlot accepts it.
_TRAILING_COMMA_RE = re.compile(
    r",\s*\n\s*(FROM|WHERE|GROUP\s+BY|HAVING|ORDER\s+BY|LIMIT|UNION|"
    r"EXCEPT|INTERSECT|WINDOW)\b(?!\s*,)",
    re.IGNORECASE,
)
_TRAILING_COMMA_CONSTRUCT = "trailing comma before FROM/WHERE/..."


class Violation(NamedTuple):
    filepath: str
    line_no: int
    construct: str
    text: str


def _strip_line_comment(line: str) -> str:
    return _COMMENT_RE.sub("", line)


def _strip_string_literals(line: str) -> str:
    return _STRING_LITERAL_RE.sub("''", line)


def _blank_preserving_newlines(match: "re.Match[str]") -> str:
    return " " + "\n" * match.group(0).count("\n")


def _replace_string_preserving_newlines(match: "re.Match[str]") -> str:
    return "''" + "\n" * match.group(0).count("\n")


def _normalize_sql_for_trailing_comma(sql: str) -> str:
    sql = _BLOCK_COMMENT_RE.sub(_blank_preserving_newlines, sql)
    sql = _LINE_COMMENT_RE.sub("", sql)
    return _STRING_LITERAL_RE.sub(_replace_string_preserving_newlines, sql)


def _scan_trailing_select_commas(text: str, filepath: str) -> List[Violation]:
    normalized = _normalize_sql_for_trailing_comma(text)
    raw_lines = text.splitlines()
    violations: List[Violation] = []
    for match in _TRAILING_COMMA_RE.finditer(normalized):
        line_no = normalized[: match.start()].count("\n") + 1
        raw_line = (
            raw_lines[line_no - 1].strip() if 0 < line_no <= len(raw_lines) else ""
        )
        violations.append(
            Violation(
                filepath=filepath,
                line_no=line_no,
                construct=_TRAILING_COMMA_CONSTRUCT,
                text=raw_line,
            )
        )
    return violations


def scan_sql_text(sql: str, filepath: str) -> List[Violation]:
    violations: List[Violation] = []
    lines = sql.splitlines()
    for line_no, raw_line in enumerate(lines, start=1):
        stripped = _strip_string_literals(_strip_line_comment(raw_line))
        for construct, pattern in _CONSTRUCTS:
            if pattern.search(stripped):
                violations.append(
                    Violation(
                        filepath=filepath,
                        line_no=line_no,
                        construct=construct,
                        text=raw_line.strip(),
                    )
                )
                break  # one Databricks-construct violation per line is enough
    violations.extend(_scan_trailing_select_commas(sql, filepath))
    return violations


def scan_file(path: Path) -> List[Violation]:
    try:
        sql = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"WARNING: cannot read {path}: {exc}", file=sys.stderr)
        return []
    return scan_sql_text(sql, str(path))


def get_changed_sql_files(branch: str) -> List[Path]:
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    diff: Dict[str, str] = git_service.get_modified_files_from_diff(from_ref, "HEAD")
    return [
        Path(filepath)
        for filepath, status in diff.items()
        if filepath.endswith(".sql")
        and status in git_service.UPSERT_STATUS_CODES
        and not filepath.startswith("dags/platform/migration_")
    ]


def get_all_sql_files() -> List[Path]:
    return list(Path("dags").rglob("*.sql"))


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Fail if changed SQL files contain Databricks-only constructs "
            "or Spark-rejected trailing commas in SELECT lists."
        )
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
        print("OK: No Databricks-specific constructs or trailing SELECT commas found.")
        return 0

    print(
        f"\n❌  Found {len(all_violations)} Spark-incompatible construct(s) "
        "(Databricks-only syntax or trailing SELECT comma):\n",
        file=sys.stderr,
    )
    for v in all_violations:
        print(
            f"  {v.filepath}:{v.line_no}: [{v.construct}]\n      {v.text}",
            file=sys.stderr,
        )
    print(
        "\nRewrite Databricks-only constructs to standard Spark SQL "
        "(see .cursor/skills/databricks-emr-migration/). "
        "Remove trailing commas immediately before FROM / WHERE / GROUP BY / "
        "HAVING / ORDER BY / LIMIT / UNION / EXCEPT / INTERSECT / WINDOW.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
