#!/usr/bin/env python3
"""
Parse Airflow DAG File Processing Stats logs (before/after a deployment) and report:
- What improved significantly
- What didn't change much
- Next DAGs to prioritize for parse-time optimization

Accepts multiple snapshots per period; runtimes are averaged across snapshots before
comparing, which smooths out per-cycle variance.

Usage (single snapshot):
  python scripts/analysis/parse_processor_logs.py \\
    --before ~/Desktop/bietlejuice-processor-before.txt \\
    --after  ~/Desktop/bietlejuice-processor-after-1h.txt

Usage (multiple snapshots, averaged):
  python scripts/analysis/parse_processor_logs.py \\
    --before temp/dag-processor-before*.txt \\
    --after  temp/dag-processor-later*.txt

Usage (next chunk, after finishing top 30):
  python scripts/analysis/parse_processor_logs.py \\
    --before temp/dag-processor-before*.txt --after temp/dag-processor-later*.txt \\
    --skip-first 30

Output: printed summary + report written to temp/ by default.
"""

from __future__ import annotations

import argparse
import re
import statistics
import sys
from dataclasses import dataclass
from math import ceil
from pathlib import Path

# Default output directory
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent.parent / "temp"
DEFAULT_OUTPUT_MD = DEFAULT_OUTPUT_DIR / "bietlejuice-processor-report.md"


# Pattern: Last Runtime (X.XXs), then timestamp, then DB queries at end of line
LAST_RUNTIME_RE = re.compile(
    r"([\d.]+)s\s+(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s+(\d+)\s*$"
)


@dataclass
class DagStat:
    file_path: str
    basename: str
    last_runtime_s: float
    last_run: str
    db_queries: int

    @property
    def short_name(self) -> str:
        """Unique-enough name for grouping (e.g. gsheets_static_dag.py)."""
        return self.basename

    @property
    def identity(self) -> str:
        """Stable path relative to the DAG root, including bundle domain."""
        marker = "/usr/local/airflow/dags/"
        if marker not in self.file_path:
            return self.file_path
        relative = self.file_path.split(marker, 1)[1]
        # Older snapshots included a duplicated dags/ path component.
        return relative.removeprefix("dags/")


def parse_log_file(path: Path) -> list[DagStat]:
    """Parse an Airflow DAG File Processing Stats log. Returns list of DagStat."""
    text = path.read_text()
    lines = text.splitlines()
    stats = []
    for line in lines:
        if not line.strip() or "File Path" in line or "---" in line or "====" in line:
            continue
        if not line.strip().startswith("/"):
            continue
        match = LAST_RUNTIME_RE.search(line)
        if not match:
            continue
        last_runtime_s = float(match.group(1))
        last_run = match.group(2)
        db_queries = int(match.group(3))
        # File path is everything before the "Last Runtime" column; path ends with .py
        idx = line.rfind(".py")
        if idx == -1:
            continue
        file_path = line[: idx + 3].rstrip()
        basename = Path(file_path).name
        stats.append(
            DagStat(
                file_path=file_path,
                basename=basename,
                last_runtime_s=last_runtime_s,
                last_run=last_run,
                db_queries=db_queries,
            )
        )
    return stats


def build_by_identity(stats: list[DagStat]) -> dict[str, DagStat]:
    """Index by normalized relative path so domain bundles cannot collide."""
    by_identity: dict[str, DagStat] = {}
    for s in stats:
        by_identity[s.identity] = s
    return by_identity


def average_snapshots(file_paths: list[Path]) -> dict[str, DagStat]:
    """Parse multiple snapshot files and return per-DAG averaged stats.

    For each file (keyed by normalized relative path) ``last_runtime_s`` and ``db_queries``
    are averaged across all snapshots that contain the DAG.  ``last_run`` and
    ``file_path`` are taken from the first snapshot that includes the DAG.
    """
    from collections import defaultdict

    runtime_buckets: dict[str, list[float]] = defaultdict(list)
    db_query_buckets: dict[str, list[int]] = defaultdict(list)
    first_seen: dict[str, DagStat] = {}

    for path in file_paths:
        snapshot = build_by_identity(parse_log_file(path))
        for identity, stat in snapshot.items():
            runtime_buckets[identity].append(stat.last_runtime_s)
            db_query_buckets[identity].append(stat.db_queries)
            if identity not in first_seen:
                first_seen[identity] = stat

    averaged: dict[str, DagStat] = {}
    for identity, runtimes in runtime_buckets.items():
        proto = first_seen[identity]
        averaged[identity] = DagStat(
            file_path=proto.file_path,
            basename=proto.basename,
            last_runtime_s=sum(runtimes) / len(runtimes),
            last_run=proto.last_run,
            db_queries=round(
                sum(db_query_buckets[identity]) / len(db_query_buckets[identity])
            ),
        )
    return averaged


def summarize_period(stats: dict[str, DagStat]) -> dict:
    """Return topology-independent period metrics for bundle migrations."""
    runtimes = sorted(stat.last_runtime_s for stat in stats.values())
    db_queries = [stat.db_queries for stat in stats.values()]
    if not runtimes:
        return {
            "files": 0,
            "total_runtime_s": 0.0,
            "mean_runtime_s": 0.0,
            "median_runtime_s": 0.0,
            "p90_runtime_s": 0.0,
            "max_runtime_s": 0.0,
            "mean_db_queries": 0.0,
            "max_db_queries": 0,
        }
    # Nearest-rank empirical percentile. Unlike flooring an index over n - 1,
    # this cannot put p90 below the median for small periods.
    p90_index = ceil(0.9 * len(runtimes)) - 1
    return {
        "files": len(runtimes),
        "total_runtime_s": sum(runtimes),
        "mean_runtime_s": statistics.mean(runtimes),
        "median_runtime_s": statistics.median(runtimes),
        "p90_runtime_s": runtimes[p90_index],
        "max_runtime_s": runtimes[-1],
        "mean_db_queries": statistics.mean(db_queries),
        "max_db_queries": max(db_queries),
    }


def _compute_analysis(
    before: dict[str, DagStat],
    after: dict[str, DagStat],
    *,
    significant_improvement_pct: float,
    significant_improvement_abs_s: float,
    unchanged_pct_threshold: float,
    still_slow_threshold_s: float,
    top_n_next: int,
    top_n_80_20: int = 30,
    skip_first: int = 0,
) -> dict:
    common = set(before) & set(after)
    only_before = set(before) - set(after)
    only_after = set(after) - set(before)
    paired = [(b, before[b], after[b]) for b in sorted(common)]
    before_summary = summarize_period(before)
    after_summary = summarize_period(after)
    all_identities = set(before) | set(after)
    topology_overlap = len(common) / len(all_identities) if all_identities else 0.0
    topology_comparable = topology_overlap >= 0.5
    cycle_delta_s = after_summary["total_runtime_s"] - before_summary["total_runtime_s"]
    cycle_delta_pct = (
        cycle_delta_s / before_summary["total_runtime_s"] * 100
        if before_summary["total_runtime_s"]
        else 0.0
    )
    total_before = sum(s.last_runtime_s for _, s, _ in paired)
    total_after = sum(s.last_runtime_s for _, _, s in paired)
    delta_s = total_after - total_before
    delta_pct = (total_after / total_before - 1) * 100 if total_before else 0

    improved = []
    for basename, b_stat, a_stat in paired:
        d_s = a_stat.last_runtime_s - b_stat.last_runtime_s
        pct = (d_s / b_stat.last_runtime_s) * 100 if b_stat.last_runtime_s else 0
        if (
            d_s <= -significant_improvement_abs_s
            and pct <= -significant_improvement_pct
        ):
            improved.append(
                (basename, b_stat.last_runtime_s, a_stat.last_runtime_s, d_s, pct)
            )
    improved.sort(key=lambda x: x[1], reverse=True)

    unchanged = []
    for basename, b_stat, a_stat in paired:
        if b_stat.last_runtime_s <= 0:
            continue
        pct = (
            (a_stat.last_runtime_s - b_stat.last_runtime_s) / b_stat.last_runtime_s
        ) * 100
        if (
            -unchanged_pct_threshold <= pct <= unchanged_pct_threshold
            and b_stat.last_runtime_s >= 3.0
        ):
            unchanged.append(
                (basename, b_stat.last_runtime_s, a_stat.last_runtime_s, pct)
            )
    unchanged.sort(key=lambda x: x[1], reverse=True)

    regressed = []
    for basename, b_stat, a_stat in paired:
        d_s = a_stat.last_runtime_s - b_stat.last_runtime_s
        if d_s > 1.0:
            pct = (d_s / b_stat.last_runtime_s) * 100 if b_stat.last_runtime_s else 0
            regressed.append(
                (basename, b_stat.last_runtime_s, a_stat.last_runtime_s, d_s, pct)
            )
    regressed.sort(key=lambda x: x[3], reverse=True)

    still_slow = [
        (basename, after[basename].last_runtime_s, before[basename].last_runtime_s)
        for basename in common
        if after[basename].last_runtime_s >= still_slow_threshold_s
    ]
    still_slow.sort(key=lambda x: x[1], reverse=True)

    # 80/20: DAGs sorted by After runtime (desc); two views:
    # - pareto_80: smallest set that reaches 80% of total parse time (can be many DAGs)
    # - top_n_80_20: first N that reach at least 20% of total (actionable short list), or top_n
    by_after = [
        (basename, after[basename].last_runtime_s, before[basename].last_runtime_s)
        for basename in common
    ]
    by_after.sort(key=lambda x: x[1], reverse=True)
    pareto_80_target = 0.80
    cum = 0.0
    pareto_80 = []
    for basename, a_s, b_s in by_after:
        cum += a_s
        pct = (cum / total_after) * 100 if total_after else 0
        pareto_80.append((basename, a_s, b_s, cum, pct))
        if cum >= total_after * pareto_80_target:
            break
    # Actionable 80/20: top DAGs that together reach 20% of total (or top_n_80_20), whichever is shorter.
    # skip_first skips that many already-investigated DAGs for the "next chunk".
    cum20 = 0.0
    target_20pct = total_after * 0.20
    top_n_80_20_list = []
    for i, (basename, a_s, b_s) in enumerate(by_after):
        if i < skip_first:
            continue
        cum20 += a_s
        pct = (cum20 / total_after) * 100 if total_after else 0
        top_n_80_20_list.append((basename, a_s, b_s, cum20, pct))
        if len(top_n_80_20_list) >= top_n_80_20 or cum20 >= target_20pct:
            break

    return {
        "n_common": len(common),
        "n_only_before": len(only_before),
        "n_only_after": len(only_after),
        "before_summary": before_summary,
        "after_summary": after_summary,
        "topology_overlap": topology_overlap,
        "topology_comparable": topology_comparable,
        "cycle_delta_s": cycle_delta_s,
        "cycle_delta_pct": cycle_delta_pct,
        "total_before": total_before,
        "total_after": total_after,
        "delta_s": delta_s,
        "delta_pct": delta_pct,
        "improved": improved,
        "unchanged": unchanged,
        "regressed": regressed,
        "still_slow": still_slow[:top_n_next],
        "still_slow_threshold_s": still_slow_threshold_s,
        "significant_improvement_pct": significant_improvement_pct,
        "significant_improvement_abs_s": significant_improvement_abs_s,
        "pareto_80": pareto_80,
        "pareto_80_target_pct": pareto_80_target * 100,
        "top_n_80_20": top_n_80_20_list,
    }


def format_text(
    before_paths: list[Path],
    after_paths: list[Path],
    data: dict,
) -> str:
    """Plain text report."""
    before_label = (
        str(before_paths[0])
        if len(before_paths) == 1
        else f"{len(before_paths)} snapshots: {', '.join(p.name for p in before_paths)}"
    )
    after_label = (
        str(after_paths[0])
        if len(after_paths) == 1
        else f"{len(after_paths)} snapshots: {', '.join(p.name for p in after_paths)}"
    )
    lines = [
        "=" * 80,
        "DAG PARSE TIME: BEFORE vs AFTER",
        "=" * 80,
        f"Before: {before_label}",
        f"After:  {after_label}",
        f"Common DAGs: {data['n_common']}  |  Only before: {data['n_only_before']}  |  Only after: {data['n_only_after']}",
        "",
        "--- Summary ---",
        "Topology-independent period metrics:",
        (
            f"  Files: {data['before_summary']['files']} → "
            f"{data['after_summary']['files']}"
        ),
        (
            f"  Sum of Last Runtime (all files): "
            f"{data['before_summary']['total_runtime_s']:.1f}s → "
            f"{data['after_summary']['total_runtime_s']:.1f}s "
            f"({data['cycle_delta_s']:+.1f}s, {data['cycle_delta_pct']:+.1f}%)"
        ),
        (
            f"  Mean / median / p90: "
            f"{data['before_summary']['mean_runtime_s']:.2f}s / "
            f"{data['before_summary']['median_runtime_s']:.2f}s / "
            f"{data['before_summary']['p90_runtime_s']:.2f}s → "
            f"{data['after_summary']['mean_runtime_s']:.2f}s / "
            f"{data['after_summary']['median_runtime_s']:.2f}s / "
            f"{data['after_summary']['p90_runtime_s']:.2f}s"
        ),
        f"Sum of Last Runtime (common DAGs):  Before {data['total_before']:.1f}s  →  After {data['total_after']:.1f}s  ({data['delta_s']:+.1f}s, {data['delta_pct']:+.1f}%)",
        "",
    ]
    if not data["topology_comparable"]:
        lines.extend(
            [
                "NOTE: file topology changed; use all-file period metrics, not paired-DAG deltas.\n",
            ]
        )
    lines.append(
        f"--- 80/20: PRIORITIZE THESE ({len(data['top_n_80_20'])} DAGs = "
        f"{(data['top_n_80_20'][-1][4] if data['top_n_80_20'] else 0):.1f}% "
        "of parse time) ---"
    )
    for i, (basename, a_s, b_s, cum_s, cum_pct) in enumerate(data["top_n_80_20"], 1):
        delta_pct = ((a_s - b_s) / b_s * 100) if b_s else 0
        lines.append(
            f"  {i:2}. {basename:50}  After: {a_s:5.2f}s  Before: {b_s:5.2f}s  ({delta_pct:+.0f}%)  cum: {cum_pct:.1f}%"
        )
    lines.extend(
        [
            "",
            f"--- 1) IMPROVED SIGNIFICANTLY (≥{data['significant_improvement_pct']:.0f}% and ≥{data['significant_improvement_abs_s']:.0f}s faster) ---",
        ]
    )
    if not data["improved"]:
        lines.append("(none)")
    else:
        for basename, b_s, a_s, delta_s, pct in data["improved"]:
            lines.append(
                f"  {basename:55}  {b_s:6.2f}s → {a_s:6.2f}s   ({delta_s:+.2f}s, {pct:+.0f}%)"
            )
    lines.extend(["", "--- 2) LITTLE OR NO CHANGE (within ±15%, and was ≥3s) ---"])
    if not data["unchanged"]:
        lines.append("(none)")
    else:
        for basename, b_s, a_s, pct in data["unchanged"][:40]:
            lines.append(f"  {basename:55}  {b_s:6.2f}s → {a_s:6.2f}s   ({pct:+.0f}%)")
        if len(data["unchanged"]) > 40:
            lines.append(f"  ... and {len(data['unchanged']) - 40} more")
    lines.extend(["", "--- 3) REGRESSIONS (>1s slower) ---"])
    if not data["regressed"]:
        lines.append("(none)")
    else:
        for basename, b_s, a_s, delta_s, pct in data["regressed"]:
            lines.append(
                f"  {basename:55}  {b_s:6.2f}s → {a_s:6.2f}s   ({delta_s:+.2f}s, {pct:+.0f}%)"
            )
    lines.extend(
        [
            "",
            f"--- 4) NEXT TO OPTIMIZE (still ≥{data['still_slow_threshold_s']}s parse time) ---",
        ]
    )
    for basename, a_s, b_s in data["still_slow"]:
        delta = a_s - b_s
        pct = (delta / b_s * 100) if b_s else 0
        lines.append(
            f"  {basename:55}  After: {a_s:6.2f}s  (before: {b_s:6.2f}s, {pct:+.0f}%)"
        )
    lines.extend(["", "=" * 80])
    return "\n".join(lines)


def format_markdown(
    before_paths: list[Path],
    after_paths: list[Path],
    data: dict,
) -> str:
    """Markdown report with tables and summary."""
    th = data["still_slow_threshold_s"]
    pct_rule = data["significant_improvement_pct"]
    abs_rule = data["significant_improvement_abs_s"]

    n_improved = len(data["improved"])
    n_regressed = len(data["regressed"])

    n_before = len(before_paths)
    n_after = len(after_paths)
    averaged_note = (
        f"Each period averaged across **{n_before} before** and **{n_after} after** snapshots."
        if n_before > 1 or n_after > 1
        else "Single snapshot per period."
    )
    topology_note = (
        ""
        if data["topology_comparable"]
        else (
            "> **File topology changed.** Use the all-file cycle metrics; "
            "paired-DAG deltas are not representative."
        )
    )

    lines = [
        "# DAG Parse Time: Before vs After",
        "",
        f"Comparison of Airflow DAG file processing (parse) times before and after a deployment. {averaged_note}",
        "",
        "## Key metrics",
        "",
        "| Metric | Value |",
        "|--------|-------|",
        f"| **All-file cycle gain** | **{data['cycle_delta_s']:+.1f}s** ({data['cycle_delta_pct']:+.1f}%) |",
        f"| **Total gain** | **{data['delta_s']:+.1f}s** ({data['delta_pct']:+.1f}%) over {data['n_common']} DAGs |",
        f"| **Improved significantly** | {n_improved} DAGs (≥{data['significant_improvement_pct']:.0f}% and ≥{data['significant_improvement_abs_s']:.0f}s faster) |",
        f"| **Little or no change** | {len(data['unchanged'])} DAGs (within ±15%) |",
        f"| **Regressions (>1s slower)** | {n_regressed} DAGs (may be variance) |",
        f"| **Still ≥{th}s (next to optimize)** | {len(data['still_slow'])} DAGs listed below |",
        f"| **Prioritize first (80/20)** | Top **{len(data['top_n_80_20'])}** DAGs = **{(data['top_n_80_20'][-1][4] if data['top_n_80_20'] else 0):.1f}%** of parse time |",
        "",
        "---",
        "",
        "## Sources",
        "",
        "| Period | Snapshots |",
        "|--------|-----------|",
        f"| **Before** | {', '.join(f'`{p.name}`' for p in before_paths)} |",
        f"| **After**  | {', '.join(f'`{p.name}`' for p in after_paths)} |",
        "",
        "---",
        "",
        "## Summary",
        "",
        topology_note,
        "" if topology_note else "",
        "| Metric | Value |",
        "|--------|-------|",
        f"| Common DAGs (in both logs) | {data['n_common']} |",
        f"| Only in Before | {data['n_only_before']} |",
        f"| Only in After  | {data['n_only_after']} |",
        "",
        "### Topology-independent all-file metrics",
        "",
        "| Metric | Before | After |",
        "|--------|--------|-------|",
        f"| Files | {data['before_summary']['files']} | {data['after_summary']['files']} |",
        f"| Total runtime | {data['before_summary']['total_runtime_s']:.1f}s | {data['after_summary']['total_runtime_s']:.1f}s |",
        f"| Mean | {data['before_summary']['mean_runtime_s']:.2f}s | {data['after_summary']['mean_runtime_s']:.2f}s |",
        f"| Median | {data['before_summary']['median_runtime_s']:.2f}s | {data['after_summary']['median_runtime_s']:.2f}s |",
        f"| p90 | {data['before_summary']['p90_runtime_s']:.2f}s | {data['after_summary']['p90_runtime_s']:.2f}s |",
        "",
        "### Total parse time (sum of Last Runtime, common DAGs only)",
        "",
        "| | Seconds |",
        "|---|--------|",
        f"| **Before** | {data['total_before']:.1f}s |",
        f"| **After**  | {data['total_after']:.1f}s |",
        f"| **Change** | **{data['delta_s']:+.1f}s** ({data['delta_pct']:+.1f}%) |",
        "",
        "---",
        "",
        "## Next to work on (80/20)",
        "",
        f"Prioritize the **{len(data['top_n_80_20'])} DAGs** below (top by parse time). They account for **{(data['top_n_80_20'][-1][4] if data['top_n_80_20'] else 0):.1f}%** of total parse time. Fixing these first gives the best return.",
        "",
        "| # | DAG | After | Before | Δ (%) | Cumulative % |",
        "|---|-----|-------|--------|-------|--------------|",
    ]
    for i, (basename, a_s, b_s, cum_s, cum_pct) in enumerate(data["top_n_80_20"], 1):
        delta_pct = ((a_s - b_s) / b_s * 100) if b_s else 0
        lines.append(
            f"| {i} | `{basename}` | {a_s:.2f}s | {b_s:.2f}s | {delta_pct:+.0f}% | {cum_pct:.1f}% |"
        )
    lines.extend(
        [
            "",
            "---",
            "",
            f"## 1. Improved significantly (≥{pct_rule:.0f}% and ≥{abs_rule:.0f}s faster)",
            "",
            "| DAG | Before | After | Δ (s) | Δ (%) |",
            "|-----|--------|-------|-------|-------|",
        ]
    )
    if not data["improved"]:
        lines.append("| *(none)* | | | | |")
    else:
        for basename, b_s, a_s, delta_s, pct in data["improved"]:
            lines.append(
                f"| `{basename}` | {b_s:.2f}s | {a_s:.2f}s | {delta_s:+.2f}s | {pct:+.0f}% |"
            )
    lines.extend(
        [
            "",
            "---",
            "",
            "## 2. Little or no change (within ±15%, and was ≥3s)",
            "",
            "| DAG | Before | After | Δ (%) |",
            "|-----|--------|-------|-------|",
        ]
    )
    if not data["unchanged"]:
        lines.append("| *(none)* | | | |")
    else:
        for basename, b_s, a_s, pct in data["unchanged"][:50]:
            lines.append(f"| `{basename}` | {b_s:.2f}s | {a_s:.2f}s | {pct:+.0f}% |")
        if len(data["unchanged"]) > 50:
            lines.append(f"| *... and {len(data['unchanged']) - 50} more* | | | |")
    lines.extend(
        [
            "",
            "---",
            "",
            "## 3. Regressions (>1s slower)",
            "",
            "*These may be variance (parse order / load); re-run or re-sample to confirm.*",
            "",
            "| DAG | Before | After | Δ (s) | Δ (%) |",
            "|-----|--------|-------|-------|-------|",
        ]
    )
    if not data["regressed"]:
        lines.append("| *(none)* | | | | |")
    else:
        for basename, b_s, a_s, delta_s, pct in data["regressed"]:
            lines.append(
                f"| `{basename}` | {b_s:.2f}s | {a_s:.2f}s | {delta_s:+.2f}s | {pct:+.0f}% |"
            )
    lines.extend(
        [
            "",
            "---",
            "",
            f"## 4. Next to optimize (still ≥{th}s parse time after)",
            "",
            "Prioritize these DAGs for the next round of parse-time optimizations.",
            "",
            "| DAG | Before | After | Δ (%) |",
            "|-----|--------|-------|-------|",
        ]
    )
    for basename, a_s, b_s in data["still_slow"]:
        delta = a_s - b_s
        pct = (delta / b_s * 100) if b_s else 0
        lines.append(f"| `{basename}` | {b_s:.2f}s | {a_s:.2f}s | {pct:+.0f}% |")
    lines.append("")
    return "\n".join(lines)


def analyze(
    before_paths: list[Path],
    after_paths: list[Path],
    *,
    significant_improvement_pct: float = 50.0,
    significant_improvement_abs_s: float = 3.0,
    unchanged_pct_threshold: float = 15.0,
    still_slow_threshold_s: float = 5.0,
    top_n_next: int = 25,
    top_n_80_20: int = 30,
    skip_first: int = 0,
) -> tuple[dict, str]:
    """Run analysis and return (data, text_report). Use format_markdown(data) for MD.

    Accepts one or more snapshot files per period; runtimes are averaged when
    multiple snapshots are provided.
    """
    before = (
        average_snapshots(before_paths)
        if len(before_paths) > 1
        else build_by_identity(parse_log_file(before_paths[0]))
    )
    after = (
        average_snapshots(after_paths)
        if len(after_paths) > 1
        else build_by_identity(parse_log_file(after_paths[0]))
    )
    data = _compute_analysis(
        before,
        after,
        significant_improvement_pct=significant_improvement_pct,
        significant_improvement_abs_s=significant_improvement_abs_s,
        unchanged_pct_threshold=unchanged_pct_threshold,
        still_slow_threshold_s=still_slow_threshold_s,
        top_n_next=top_n_next,
        top_n_80_20=top_n_80_20,
        skip_first=skip_first,
    )
    text = format_text(before_paths, after_paths, data)
    return data, text


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare Airflow DAG processor logs before/after deployment. "
            "Accepts multiple snapshot files per period; runtimes are averaged when "
            "more than one snapshot is provided."
        )
    )
    parser.add_argument(
        "--before",
        type=Path,
        nargs="+",
        required=True,
        help="One or more processor stats log files BEFORE deployment (shell glob OK)",
    )
    parser.add_argument(
        "--after",
        type=Path,
        nargs="+",
        required=True,
        help="One or more processor stats log files AFTER deployment (shell glob OK)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("temp/bietlejuice-processor-report.md"),
        help="Write report to this file (default: temp/bietlejuice-processor-report.md)",
    )
    parser.add_argument(
        "--format",
        choices=("text", "markdown"),
        default=None,
        help="Output format: text (default) or markdown. If --out ends in .md, default is markdown.",
    )
    parser.add_argument(
        "--improvement-pct",
        type=float,
        default=50.0,
        help="Count as 'improved significantly' if at least this %% faster (default: 50)",
    )
    parser.add_argument(
        "--improvement-abs",
        type=float,
        default=3.0,
        help="Count as 'improved significantly' if at least this many seconds faster (default: 3)",
    )
    parser.add_argument(
        "--still-slow",
        type=float,
        default=5.0,
        help="'Next to optimize' if After runtime >= this many seconds (default: 5)",
    )
    parser.add_argument(
        "--top-next",
        type=int,
        default=25,
        help="Max number of DAGs to list in 'Next to optimize' (default: 25)",
    )
    parser.add_argument(
        "--top-80-20",
        type=int,
        default=30,
        help="Number of DAGs in 80/20 prioritize list (default: 30). Use 60 for next chunk.",
    )
    parser.add_argument(
        "--skip-first",
        type=int,
        default=0,
        help="Skip first N DAGs in 80/20 list for 'next chunk' (e.g. 30 to see DAGs 31-60)",
    )
    args = parser.parse_args()

    missing_before = [p for p in args.before if not p.exists()]
    missing_after = [p for p in args.after if not p.exists()]
    if missing_before:
        print(f"Error: --before files not found: {missing_before}", file=sys.stderr)
        return 1
    if missing_after:
        print(f"Error: --after files not found: {missing_after}", file=sys.stderr)
        return 1

    if len(args.before) > 1 or len(args.after) > 1:
        print(
            f"Averaging {len(args.before)} before snapshot(s) and {len(args.after)} after snapshot(s)...",
            file=sys.stderr,
        )

    data, text_report = analyze(
        args.before,
        args.after,
        significant_improvement_pct=args.improvement_pct,
        significant_improvement_abs_s=args.improvement_abs,
        still_slow_threshold_s=args.still_slow,
        top_n_next=args.top_next,
        top_n_80_20=args.top_80_20,
        skip_first=args.skip_first,
    )

    use_md = args.format == "markdown" or (
        args.format is None and args.out and str(args.out).lower().endswith(".md")
    )
    report = format_markdown(args.before, args.after, data) if use_md else text_report

    print(report)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report)
    print(f"Report written to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
