#!/usr/bin/env python3
"""Generate argparse smoke tests for patched validation Spark jobs."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import List, Optional

REPO_ROOT = Path(__file__).resolve().parents[4]
LIST_SCRIPT = (
    REPO_ROOT
    / "packages/bietlejuice-compiler/scripts/validation/list_validation_spark_jobs.py"
)

TEST_TEMPLATE = '''"""Argparse smoke tests for {line} custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
{job_paths}
]


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    assert "resolve_datalake_write_target" in text
'''


def _inventory(ref: str, line: str, status: str = "needs_fix") -> List[str]:
    cmd = [
        sys.executable,
        str(LIST_SCRIPT),
        "--ref",
        ref,
        "--line",
        line,
        "--status",
        status,
        "--tsv",
    ]
    result = subprocess.run(
        cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=True
    )
    paths: List[str] = []
    seen = set()
    for line_row in result.stdout.strip().splitlines()[1:]:
        cols = line_row.split("\t")
        if len(cols) < 6:
            continue
        rel = cols[5]
        if rel and rel not in seen and (REPO_ROOT / rel).exists():
            seen.add(rel)
            paths.append(rel)
    return sorted(paths)


def _patched_jobs_under_line(line: str) -> List[str]:
    dag_root = REPO_ROOT / "dags" / line
    if not dag_root.exists():
        return []
    paths = []
    for path in dag_root.rglob("spark_jobs/*.py"):
        if path.name.startswith("test_"):
            continue
        text = path.read_text(encoding="utf-8")
        if "resolve_datalake_write_target" in text and (
            "add_validation_target_args" in text or "--target-database-name" in text
        ):
            paths.append(path.relative_to(REPO_ROOT).as_posix())
    extra = [
        REPO_ROOT / "dags/cross/base/spark_jobs/load_growth_intel_crawler_raw.py",
        REPO_ROOT / "dags/cross/kong/spark_jobs/load_kong_raw.py",
        REPO_ROOT / "dags/cross/request_logging/spark_jobs/fetch_data.py",
    ]
    if line == "cross":
        for path in extra:
            if path.exists():
                text = path.read_text(encoding="utf-8")
                if "resolve_datalake_write_target" in text:
                    paths.append(path.relative_to(REPO_ROOT).as_posix())
    return sorted(set(paths))


def generate(line: str, ref: str, *, use_disk: bool = True) -> str:
    if use_disk:
        paths = _patched_jobs_under_line(line)
    else:
        paths = _inventory(ref, line)
    if not paths:
        paths = _inventory(ref, line)

    job_lines = ",\n".join(f'    "{p}",' for p in paths)
    return TEST_TEMPLATE.format(line=line, job_paths=job_lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--line", required=True)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args(argv)

    content = generate(args.line, args.ref)
    out = (
        REPO_ROOT
        / "packages/bietlejuice-runtime/test/dags"
        / args.line
        / "spark_jobs"
        / f"test_validation_spark_args_{args.line}.py"
    )
    if not content.strip() or "_JOB_PATHS = [\n]" in content:
        print(f"No patched jobs found for {args.line}", file=sys.stderr)
        return 1
    if args.write:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(content, encoding="utf-8")
        print(f"Wrote {out.relative_to(REPO_ROOT)} ({content.count(chr(10))} lines)")
    else:
        print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
