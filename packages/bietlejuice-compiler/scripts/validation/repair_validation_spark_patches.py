#!/usr/bin/env python3
"""Repair common syntax/indent issues from automated validation Spark patches."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path
from typing import Iterable, List

REPO_ROOT = Path(
    os.environ.get("BI_ETL_REPO_ROOT", Path(__file__).resolve().parents[4])
)

BROKEN_MAIN = re.compile(
    r"def main\(\s*,\s*\n\s*target_database_name: str = None,\s*\n\s*target_table_name: str = None,\s*\n\)\s*:",
    re.MULTILINE,
)


def _fix_main_signature(content: str) -> str:
    return BROKEN_MAIN.sub("def main():", content)


def _fix_resolve_outdented_block(content: str) -> str:
    """Re-indent resolve block when it was inserted outside a try/with body."""
    lines = content.splitlines(keepends=True)
    out: List[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(
            r"^[ \t]*write_database_name, write_table_name, write_location",
            line,
        ):
            prev_indent = ""
            for prev in reversed(out):
                if prev.strip():
                    m = re.match(r"^(\s+)", prev)
                    if m:
                        prev_indent = m.group(1)
                    break
            cur_m = re.match(r"^(\s*)", line)
            cur_indent = cur_m.group(1) if cur_m else ""
            if prev_indent and len(cur_indent) < len(prev_indent):
                block = []
                while i < len(lines):
                    block.append(lines[i])
                    if re.match(r"^[ \t]*\)\s*$", lines[i]):
                        i += 1
                        break
                    i += 1
                for bl in block:
                    stripped = bl.strip()
                    if not stripped:
                        continue
                    if stripped.startswith("write_database_name"):
                        out.append(f"{prev_indent}{stripped}\n")
                    elif stripped == ")":
                        out.append(f"{prev_indent}{stripped}\n")
                    else:
                        out.append(f"{prev_indent}    {stripped}\n")
                continue
        out.append(line)
        i += 1
    return "".join(out)


def _fix_resolve_indent(content: str) -> str:
    lines = content.splitlines(keepends=True)
    out: List[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(
            r"^[ \t]{1,3}write_database_name, write_table_name, write_location",
            line,
        ):
            block = [line]
            i += 1
            while i < len(lines):
                block.append(lines[i])
                if re.match(r"^[ \t]*\)\s*$", lines[i]):
                    i += 1
                    break
                i += 1
            indent = "    "
            for prev in reversed(out):
                if prev.strip():
                    m = re.match(r"^(\s+)", prev)
                    if m:
                        indent = m.group(1)
                    break
            fixed: List[str] = []
            for idx, bl in enumerate(block):
                stripped = bl.strip()
                if not stripped:
                    continue
                if idx == 0:
                    fixed.append(f"{indent}{stripped}\n")
                elif stripped == ")":
                    fixed.append(f"{indent}{stripped}\n")
                else:
                    fixed.append(f"{indent}    {stripped}\n")
            out.extend(fixed)
            continue
        out.append(line)
        i += 1
    return "".join(out)


def _fix_bad_create_database_kwarg(content: str) -> str:
    return content.replace(
        "create_database(write_database_name=write_database_name)",
        "create_database(write_database_name)",
    )


def repair_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    updated = _fix_bad_create_database_kwarg(original)
    updated = _fix_main_signature(updated)
    updated = _fix_resolve_outdented_block(updated)
    updated = _fix_resolve_indent(updated)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        return True
    return False


def iter_spark_jobs(root: Path) -> Iterable[Path]:
    for path in root.rglob("spark_jobs/*.py"):
        if path.name.startswith("test_"):
            continue
        text = path.read_text(encoding="utf-8")
        if "resolve_datalake_write_target" in text or "def main(," in text:
            yield path


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="Files or directories")
    parser.add_argument("--line", help="Repair all patched jobs under dags/<line>/")
    args = parser.parse_args(argv)

    targets: List[Path] = []
    if args.line:
        targets.extend(iter_spark_jobs(REPO_ROOT / "dags" / args.line))
        if args.line == "cross":
            for extra in (
                "dags/cross/base/spark_jobs",
                "dags/cross/kong/spark_jobs",
                "dags/cross/request_logging/spark_jobs",
            ):
                targets.extend(iter_spark_jobs(REPO_ROOT / extra))
    for raw in args.paths:
        p = REPO_ROOT / raw if not Path(raw).is_absolute() else Path(raw)
        if p.is_dir():
            targets.extend(iter_spark_jobs(p))
        elif p.is_file():
            targets.append(p)

    seen = set()
    repaired = 0
    for path in sorted(set(targets)):
        if path in seen or not path.exists():
            continue
        seen.add(path)
        if repair_file(path):
            repaired += 1
            print(f"REPAIRED: {path.relative_to(REPO_ROOT)}")

    print(f"Repaired {repaired} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
