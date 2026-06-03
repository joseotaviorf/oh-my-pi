#!/usr/bin/env python3
"""
Inventory custom Spark jobs behind allow_custom_spark_job cluster validation DAGs.

Usage:
  python list_validation_spark_jobs.py --ref origin/DPLT-1288/cluster-validation-fintech
  python list_validation_spark_jobs.py --ref origin/master --line fintech --tsv
  python list_validation_spark_jobs.py --all-validation-branches --tsv
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

REPO_ROOT = Path(__file__).resolve().parents[4]


@dataclass
class SparkJobEntry:
    branch: str
    line: str
    cluster_file: str
    spark_job_name: str
    spark_job_path: Optional[str]
    status: str
    dag_filter: str


def _run(cmd: List[str]) -> str:
    result = subprocess.run(
        cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        return ""
    return result.stdout


def git_show(ref: str, path: str) -> str:
    return _run(["git", "show", f"{ref}:{path}"])


def git_grep_files(ref: str, pattern: str, path: str = "dags/") -> List[str]:
    out = _run(["git", "grep", "-l", pattern, ref, "--", path])
    if not out:
        return []
    return [line.split(":", 1)[-1] for line in out.strip().splitlines()]


def list_remote_validation_branches() -> List[str]:
    out = _run(["git", "branch", "-r"])
    branches = []
    for line in out.splitlines():
        line = line.strip()
        if "cluster-validation-" not in line or "origin/" not in line:
            continue
        branches.append(line.replace("origin/", ""))
    return sorted(set(branches))


def _load_spark_jobs_from_declaration(text: str) -> List[tuple[str, str]]:
    """Return (context, job_name) from workflow and tables_customization."""
    jobs: List[tuple[str, str]] = []
    if not text:
        return jobs
    workflow_match = re.search(r"^\s*load_spark_job:\s*(\S+)", text, re.MULTILINE)
    if workflow_match:
        jobs.append(("workflow", workflow_match.group(1)))
    for block in re.finditer(r"tables_customization:.*?(?=\n\w|\Z)", text, re.DOTALL):
        section = block.group(0)
        table_match = re.search(r"^\s+(\w+):\s*\n", section, re.MULTILINE)
        table_key = table_match.group(1) if table_match else "table"
        job_match = re.search(r"load_spark_job:\s*(\S+)", section)
        if job_match:
            jobs.append((f"tables_customization.{table_key}", job_match.group(1)))
    return jobs


def _job_name_variants(job_name: str) -> List[str]:
    names = [job_name]
    if job_name.endswith("_raw"):
        names.append(job_name[: -len("_raw")])
    else:
        names.append(f"{job_name}_raw")
    seen: List[str] = []
    for name in names:
        if name not in seen:
            seen.append(name)
    return seen


def _resolve_spark_job_path(
    ref: str, cluster_file: str, job_name: str
) -> Optional[str]:
    if "{" in job_name or "}" in job_name:
        return None

    dag_dir = str(Path(cluster_file).parent)
    line_root = Path(cluster_file).parts[1] if cluster_file.startswith("dags/") else ""

    candidates: List[str] = []
    listing = _run(["git", "ls-tree", "-r", "--name-only", ref, "dags/"])
    if not listing:
        return None

    for variant in _job_name_variants(job_name):
        for rel in listing.splitlines():
            if not rel.endswith(f"{variant}.py") or "spark_jobs" not in rel:
                continue
            if rel.startswith(f"{dag_dir}/"):
                candidates.append(rel)
            elif (
                line_root
                and rel.startswith(f"dags/{line_root}/")
                and rel.endswith(f"{variant}.py")
            ):
                candidates.append(rel)

    if not candidates:
        for variant in _job_name_variants(job_name):
            for shared in (
                f"dags/cross/base/spark_jobs/{variant}.py",
                f"dags/{line_root}/base/spark_jobs/{variant}.py" if line_root else "",
            ):
                if shared and git_show(ref, shared):
                    return shared
        return None

    candidates.sort(key=lambda p: (p.count("/"), len(p)))
    return candidates[0]


def classify_spark_job(content: str) -> str:
    if "add_validation_target_args" in content:
        return "has_helper"
    if re.search(r"BaseCoreModelSparkJob|Core\w+BaseSparkJob", content):
        return "core_base"
    if "--target-database-name" in content:
        return "inline_flags"
    return "needs_fix"


def _line_from_branch(branch: str) -> str:
    if "cluster-validation-" in branch:
        return branch.split("cluster-validation-", 1)[-1]
    return ""


def inventory_branch(
    ref: str,
    *,
    line_filter: Optional[str] = None,
    dag_line_prefix: Optional[str] = None,
) -> List[SparkJobEntry]:
    branch = ref.replace("origin/", "")
    line = _line_from_branch(branch) or (line_filter or "")
    prefix = dag_line_prefix or (f"dags/{line}/" if line else "dags/")
    entries: List[SparkJobEntry] = []

    cluster_files = [
        f
        for f in git_grep_files(ref, "allow_custom_spark_job: true", "dags/")
        if f.endswith("_cluster.yml")
    ]

    for cluster_file in sorted(cluster_files):
        if line_filter and not cluster_file.startswith(prefix):
            if not (line_filter == "cross" and cluster_file.startswith("dags/cross/")):
                continue

        decl_path = cluster_file.replace("_cluster.yml", "_declaration.yml")
        decl_text = git_show(ref, decl_path)
        for context, job_name in _load_spark_jobs_from_declaration(decl_text):
            if "{" in job_name or "}" in job_name:
                entries.append(
                    SparkJobEntry(
                        branch=branch,
                        line=line,
                        cluster_file=cluster_file,
                        spark_job_name=job_name,
                        spark_job_path=None,
                        status="template_skip",
                        dag_filter=context,
                    )
                )
                continue
            spark_path = _resolve_spark_job_path(ref, cluster_file, job_name)
            if spark_path:
                content = git_show(ref, spark_path)
                status = classify_spark_job(content)
            else:
                status = "missing"
            entries.append(
                SparkJobEntry(
                    branch=branch,
                    line=line,
                    cluster_file=cluster_file,
                    spark_job_name=job_name,
                    spark_job_path=spark_path,
                    status=status,
                    dag_filter=context,
                )
            )
    return entries


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ref", help="Git ref (e.g. origin/DPLT-1288/cluster-validation-fintech)"
    )
    parser.add_argument("--line", help="Only include dags/<line>/ cluster files")
    parser.add_argument(
        "--all-validation-branches",
        action="store_true",
        help="Scan all origin/*cluster-validation-* branches",
    )
    parser.add_argument("--tsv", action="store_true", help="Tab-separated output")
    parser.add_argument(
        "--status",
        help="Filter by status (needs_fix, missing, has_helper, core_base, inline_flags)",
    )
    args = parser.parse_args(argv)

    if args.all_validation_branches:
        branches = list_remote_validation_branches()
        all_entries: List[SparkJobEntry] = []
        for branch in branches:
            all_entries.extend(
                inventory_branch(
                    f"origin/{branch}", line_filter=_line_from_branch(branch)
                )
            )
        entries = all_entries
    elif args.ref:
        entries = inventory_branch(
            args.ref if args.ref.startswith("origin/") else f"origin/{args.ref}",
            line_filter=f"dags/{args.line}/" if args.line else None,
        )
    else:
        parser.error("Provide --ref or --all-validation-branches")
        return 2

    if args.status:
        entries = [e for e in entries if e.status == args.status]

    if args.tsv:
        print(
            "branch\tline\tstatus\tcluster_file\tspark_job_name\tspark_job_path\tcontext"
        )
        for e in entries:
            print(
                f"{e.branch}\t{e.line}\t{e.status}\t{e.cluster_file}\t"
                f"{e.spark_job_name}\t{e.spark_job_path or ''}\t{e.dag_filter}"
            )
    else:
        for e in entries:
            print(
                f"{e.status:12} {e.branch:45} {e.spark_job_path or e.spark_job_name:60} "
                f"({e.cluster_file})"
            )
        needs = sum(1 for e in entries if e.status == "needs_fix")
        missing = sum(1 for e in entries if e.status == "missing")
        print(f"\nTotal: {len(entries)} | needs_fix: {needs} | missing: {missing}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
