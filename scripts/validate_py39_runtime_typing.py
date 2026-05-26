#!/usr/bin/env python3
"""Fail on PEP 604 union annotations that break at import time on Python 3.9 (EMR).

Scans bietlejuice-core, bietlejuice-runtime, and dags spark_jobs. Files with
``from __future__ import annotations`` in the first 30 lines are skipped because
annotations are not evaluated at runtime on 3.9.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

SCAN_ROOTS = (
    REPO_ROOT / "packages/bietlejuice-core/src",
    REPO_ROOT / "packages/bietlejuice-runtime/src",
    REPO_ROOT / "dags",
)

FUTURE_ANNOTATIONS = re.compile(
    r"^\s*from\s+__future__\s+import\s+annotations\s*$"
)

# Matches ``X | Y`` or ``list[str] | Y`` inside an annotation fragment.
PEP604_UNION = re.compile(r"(?:\]\s*|\b\w+\s*)\|\s*(?:None|\w+)\b")

# Annotation positions: return type or parameter/type binding (not walrus ``:=``).
ANNOTATION_CONTEXT = re.compile(r"->|(?<![:=<>])\:(?!=)")

SKIP_LINE_PATTERNS = (
    "data_interval_start | ds",
    " | {",
    " | (",
    " | set(",
    " | F.",
    " | col(",
    " | expected",
    " | actual",
    " | vr[",
    " | df[",
    " | wave",
    " | hour",
    " | minute",
    " | left",
    " | right",
    " | result",
    " | dataset",
    "keys() | ",
    '"str | None"',
    "'str | None'",
    "string|int|double",
)


def _has_future_annotations(lines: list[str], *, max_lines: int = 30) -> bool:
    for line in lines[:max_lines]:
        if FUTURE_ANNOTATIONS.match(line):
            return True
    return False


def _line_in_docstring(line_index: int, lines: list[str]) -> bool:
    """Return True when line_index is inside an unclosed triple-quoted string."""
    in_docstring = False
    delimiter = ""
    for idx, line in enumerate(lines):
        if idx > line_index:
            break
        stripped = line.strip()
        for quote in ('"""', "'''"):
            count = line.count(quote)
            if count:
                if not in_docstring:
                    if count % 2 == 1:
                        in_docstring = True
                        delimiter = quote
                elif delimiter == quote and count % 2 == 1:
                    in_docstring = False
                    delimiter = ""
        if idx == line_index and in_docstring:
            return True
    return False


def _should_skip_line(line: str) -> bool:
    if any(pattern in line for pattern in SKIP_LINE_PATTERNS):
        return True
    stripped = line.strip()
    if stripped.startswith("#"):
        return True
    if stripped.startswith('"') or stripped.startswith("'"):
        return True
    return False


def _in_string_literal(line: str, index: int) -> bool:
    """Return True when ``index`` falls inside a Python string literal."""
    in_string: str | None = None
    i = 0
    while i < index and i < len(line):
        if in_string is None:
            for quote in ('"""', "'''", '"', "'"):
                if line.startswith(quote, i):
                    in_string = quote
                    i += len(quote)
                    break
            else:
                i += 1
            continue

        if len(in_string) == 3:
            if line.startswith(in_string, i):
                in_string = None
                i += 3
            else:
                i += 1
            continue

        if line[i] == "\\":
            i += 2
            continue
        if line[i] == in_string:
            in_string = None
        i += 1

    return in_string is not None


def _has_pep604_union_outside_strings(line: str) -> bool:
    code = line.split("#", 1)[0]
    for match in PEP604_UNION.finditer(code):
        if not _in_string_literal(code, match.start()):
            return True
    return False


def _find_pep604_violations(path: Path) -> tuple[list[tuple[int, str]], bool]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(
            f"validate-py39-runtime-typing: error reading {path}: {exc}",
            file=sys.stderr,
        )
        return [], True

    lines = text.splitlines()
    if _has_future_annotations(lines):
        return [], False

    violations: list[tuple[int, str]] = []
    for line_no, line in enumerate(lines, start=1):
        if _should_skip_line(line):
            continue
        if _line_in_docstring(line_no - 1, lines):
            continue
        if not ANNOTATION_CONTEXT.search(line):
            continue
        if not _has_pep604_union_outside_strings(line):
            continue
        violations.append((line_no, line.strip()))
    return violations, False


def _iter_python_files(root: Path) -> list[Path]:
    if not root.exists():
        return []

    if root.name == "dags":
        return sorted(root.glob("**/spark_jobs/**/*.py"))

    return sorted(root.rglob("*.py"))


def collect_violations() -> tuple[list[tuple[Path, int, str]], bool]:
    findings: list[tuple[Path, int, str]] = []
    read_errors = False
    for scan_root in SCAN_ROOTS:
        for path in _iter_python_files(scan_root):
            file_violations, file_read_error = _find_pep604_violations(path)
            read_errors = read_errors or file_read_error
            for line_no, line in file_violations:
                rel = path.relative_to(REPO_ROOT)
                findings.append((rel, line_no, line))
    return findings, read_errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate EMR-deployed Python for PEP 604 annotations "
            "unsafe on Python 3.9 at runtime."
        )
    )
    parser.parse_args(argv)

    findings, read_errors = collect_violations()
    if read_errors:
        print(
            "\nvalidate-py39-runtime-typing: failed due to file read errors",
            file=sys.stderr,
        )
        return 1

    if not findings:
        print("validate-py39-runtime-typing: OK (no unsafe PEP 604 annotations)")
        return 0

    print(
        "validate-py39-runtime-typing: found PEP 604 annotations "
        "unsafe on Python 3.9 (use Optional/Union from typing, or add "
        "``from __future__ import annotations``):",
        file=sys.stderr,
    )
    for rel_path, line_no, line in findings:
        print(f"  {rel_path}:{line_no}: {line}", file=sys.stderr)
    print(f"\n{len(findings)} violation(s)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
