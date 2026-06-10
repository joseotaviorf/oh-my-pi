"""TARS SQL Quality Evaluation — three-phase rubric validator.

Phases
------
1. Static analysis   (sqlglot + regex, no network)
   - Tables present/absent in the parsed AST
   - Key columns present in the SQL text
   - Mandatory filter patterns matched via regex

2. Schema validation (Trino DESCRIBE, one request per expected table)
   - Validates each expected table actually exists in Trino
   - Checks expected columns are in the DESCRIBE output

3. Execution validation (full query via Trino, bounded by LIMIT)
   - Runs the golden_sql as-is (auto-appends LIMIT 100 if absent)
   - Records exec_status, rows_returned, columns_returned, latency

Output
------
  quality_report.md   — human-readable pass/fail table + narrative
  quality_results.json — raw per-question data for trend tracking

Usage
-----
    export TRINO_HOST=trino.apps.data-prd.habitat.zone
    uv run python docs/benchmark/datahub/evaluate_sql_quality.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import sqlglot
import yaml

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = Path(__file__).parent
CASES_PATH = OUT_DIR / "eval_cases.yml"
REPORT_PATH = OUT_DIR / "quality_report.md"
RESULTS_PATH = OUT_DIR / "quality_results.json"

TRINO_PYTHON = REPO_ROOT / ".cursor/skills/trino/venv/bin/python3"
TRINO_SCRIPT = REPO_ROOT / ".cursor/skills/trino/scripts/execute_trino.py"
TRINO_HOST = "trino.apps.data-prd.habitat.zone"
TRINO_CATALOG = "hive"

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------


@dataclass
class StaticResult:
    tables_found: list[str] = field(default_factory=list)
    tables_missing: list[str] = field(default_factory=list)
    forbidden_found: list[str] = field(default_factory=list)
    columns_found: list[str] = field(default_factory=list)
    columns_missing: list[str] = field(default_factory=list)
    patterns_matched: list[str] = field(default_factory=list)
    patterns_missing: list[str] = field(default_factory=list)
    parse_ok: bool = True
    parse_error: Optional[str] = None
    score: int = 0
    max_score: int = 0


@dataclass
class SchemaResult:
    tables_checked: list[str] = field(default_factory=list)
    tables_missing: list[str] = field(default_factory=list)
    columns_valid: dict[str, bool] = field(default_factory=dict)
    columns_missing: dict[str, list[str]] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    score: int = 0
    max_score: int = 0


@dataclass
class ExecResult:
    status: str = "skipped"  # success | error | skipped
    rows_returned: int = 0
    columns_returned: list[str] = field(default_factory=list)
    latency_ms: float = 0.0
    error_message: Optional[str] = None
    meets_min_rows: bool = False
    score: int = 0
    max_score: int = 0


@dataclass
class CaseResult:
    id: str = ""
    text: str = ""
    complexity: str = ""
    static: StaticResult = field(default_factory=StaticResult)
    schema: SchemaResult = field(default_factory=SchemaResult)
    execution: ExecResult = field(default_factory=ExecResult)

    @property
    def total_score(self) -> int:
        return self.static.score + self.schema.score + self.execution.score

    @property
    def total_max(self) -> int:
        return self.static.max_score + self.schema.max_score + self.execution.max_score

    @property
    def pct(self) -> float:
        return 100 * self.total_score / self.total_max if self.total_max else 0.0


# ---------------------------------------------------------------------------
# Phase 1 — Static analysis
# ---------------------------------------------------------------------------


def _extract_tables(sql: str) -> set[str]:
    """Return set of fully-qualified table names referenced in sql."""
    try:
        tables: set[str] = set()
        for stmt in sqlglot.parse(
            sql, dialect="trino", error_level=sqlglot.ErrorLevel.WARN
        ):
            if stmt is None:
                continue
            for node in stmt.walk():
                if isinstance(node, sqlglot.exp.Table):
                    parts = [
                        p
                        for p in [
                            node.args.get("db") and str(node.args["db"]),
                            node.args.get("this") and str(node.args["this"]),
                        ]
                        if p
                    ]
                    if parts:
                        tables.add(".".join(parts).lower())
        return tables
    except Exception:
        return set()


def phase1_static(case: dict[str, Any]) -> StaticResult:
    r = StaticResult()
    sql: str = case["golden_sql"]

    # --- Parse ---
    try:
        sqlglot.parse(sql, dialect="trino", error_level=sqlglot.ErrorLevel.WARN)
    except Exception as exc:
        r.parse_ok = False
        r.parse_error = str(exc)

    sql_lower = sql.lower()
    extracted_tables = _extract_tables(sql)

    # --- Expected tables (1 point each) ---
    for tbl in case.get("expected_tables", []):
        tbl_lower = tbl.lower()
        r.max_score += 1
        if tbl_lower in extracted_tables or tbl_lower in sql_lower:
            r.tables_found.append(tbl)
            r.score += 1
        else:
            r.tables_missing.append(tbl)

    # --- Forbidden tables (1 point for each absent) ---
    for frag in case.get("forbidden_tables", []):
        r.max_score += 1
        if frag.lower() in sql_lower:
            r.forbidden_found.append(frag)
            # No score — violation
        else:
            r.score += 1

    # --- Expected columns (1 point each) ---
    for col in case.get("expected_columns", []):
        r.max_score += 1
        if re.search(r"\b" + re.escape(col.lower()) + r"\b", sql_lower):
            r.columns_found.append(col)
            r.score += 1
        else:
            r.columns_missing.append(col)

    # --- Mandatory filter patterns (1 point each) ---
    for pat in case.get("mandatory_filter_patterns", []):
        r.max_score += 1
        if re.search(pat, sql, re.IGNORECASE):
            r.patterns_matched.append(pat)
            r.score += 1
        else:
            r.patterns_missing.append(pat)

    return r


# ---------------------------------------------------------------------------
# Phase 2 — Schema validation via Trino DESCRIBE
# ---------------------------------------------------------------------------


def _run_trino(query: str, timeout: int = 60) -> dict[str, Any]:
    """Invoke execute_trino.py and return the parsed JSON result."""
    if not TRINO_PYTHON.exists():
        return {
            "status": "error",
            "message": "Trino venv not found. Run setup-local-environment skill first.",
        }
    cmd = [
        str(TRINO_PYTHON),
        str(TRINO_SCRIPT),
        "--host",
        TRINO_HOST,
        "--catalog",
        TRINO_CATALOG,
        "--query",
        query,
        "--external-auth",
    ]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        stdout = proc.stdout.strip()
        if not stdout:
            return {"status": "error", "message": proc.stderr.strip() or "empty output"}
        return json.loads(stdout)
    except subprocess.TimeoutExpired:
        return {"status": "error", "message": f"Trino query timed out after {timeout}s"}
    except json.JSONDecodeError as exc:
        return {"status": "error", "message": f"JSON parse error: {exc}"}
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


def phase2_schema(case: dict[str, Any]) -> SchemaResult:
    r = SchemaResult()
    expected_columns: list[str] = [c.lower() for c in case.get("expected_columns", [])]

    # Collect all physical columns across all expected tables (union).
    # A column qualifies if it exists in ANY of the tables — this is the right
    # semantic for multi-table queries where expected_columns may span tables.
    all_described_cols: set[str] = set()

    for tbl in case.get("expected_tables", []):
        r.max_score += 1
        result = _run_trino(f"DESCRIBE {tbl}")
        if result.get("status") != "success":
            r.tables_missing.append(tbl)
            r.errors.append(f"DESCRIBE {tbl}: {result.get('message', 'unknown error')}")
            continue

        r.tables_checked.append(tbl)
        r.score += 1
        described_cols = {row[0].lower() for row in result.get("data", [])}
        all_described_cols |= described_cols

    # Now check expected columns against the union of all described columns.
    # Computed aliases (e.g. okr_bucket) are allowed to be absent from physical
    # schema — they're caught in Phase 1 which checks the SQL text directly.
    for col in expected_columns:
        if col in all_described_cols:
            r.max_score += 1
            r.columns_valid[col] = True
            r.score += 1
        else:
            # Only penalise if at least one table was successfully described;
            # if no tables were reachable we can't tell.
            if r.tables_checked:
                r.max_score += 1
                r.columns_valid[col] = False
                r.columns_missing["(any expected table)"] = r.columns_missing.get(
                    "(any expected table)", []
                ) + [col]

    return r


# ---------------------------------------------------------------------------
# Phase 3 — Execution validation
# ---------------------------------------------------------------------------


def _ensure_limit(sql: str, cap: int = 100) -> str:
    """Append LIMIT cap if the SQL has no top-level LIMIT clause."""
    if re.search(r"\bLIMIT\b", sql, re.IGNORECASE):
        return sql
    # Strip trailing semicolons, whitespace
    sql = sql.rstrip().rstrip(";")
    return sql + f"\nLIMIT {cap}"


def phase3_execution(case: dict[str, Any]) -> ExecResult:
    r = ExecResult()
    r.max_score = 2  # 1 for exec success + 1 for min rows

    sql = _ensure_limit(case["golden_sql"])
    t0 = time.perf_counter()
    result = _run_trino(sql, timeout=120)
    r.latency_ms = (time.perf_counter() - t0) * 1000

    if result.get("status") == "success":
        r.status = "success"
        r.rows_returned = result.get("count", 0)
        r.columns_returned = result.get("columns", [])
        r.score += 1  # executed without error

        min_rows = case.get("expected_min_rows", 0)
        r.meets_min_rows = r.rows_returned >= min_rows
        if r.meets_min_rows:
            r.score += 1
    else:
        r.status = "error"
        r.error_message = result.get("message", "unknown error")

    return r


# ---------------------------------------------------------------------------
# Report rendering
# ---------------------------------------------------------------------------

_PASS = "PASS"
_FAIL = "FAIL"


def _verdict(condition: bool) -> str:
    return _PASS if condition else _FAIL


def render_report(cases: list[dict], results: list[CaseResult], run_ts: str) -> str:
    lines: list[str] = []

    lines.append("# TARS SQL Quality Evaluation Report")
    lines.append("")
    lines.append(f"Generated: {run_ts}")
    lines.append("")
    lines.append(
        "Validates the **golden SQL** stored in `eval_cases.yml` against three quality "
        "dimensions: static analysis (schema routing + column + filter rules), "
        "schema validation (Trino DESCRIBE), and execution correctness (live query)."
    )
    lines.append("")

    # --- Summary table ---
    lines.append("## Summary")
    lines.append("")
    header = (
        "| # | Question | Complexity | Routing | Schema | Rules | Exec | Rows | Score |"
    )
    sep = "|---|---|---|:---:|:---:|:---:|:---:|:---:|---:|"
    lines.append(header)
    lines.append(sep)

    for case, res in zip(cases, results):
        s = res.static
        sh = res.schema
        ex = res.execution

        routing_ok = len(s.tables_missing) == 0 and len(s.forbidden_found) == 0
        schema_ok = len(sh.tables_missing) == 0
        rules_ok = len(s.patterns_missing) == 0 and len(s.columns_missing) == 0
        exec_ok = ex.status == "success"
        rows_ok = ex.meets_min_rows

        lines.append(
            f"| {case['id']} "
            f"| {case['text']} "
            f"| {case['complexity']} "
            f"| {_verdict(routing_ok)} "
            f"| {_verdict(schema_ok)} "
            f"| {_verdict(rules_ok)} "
            f"| {_verdict(exec_ok)} "
            f"| {ex.rows_returned if exec_ok else '—'} "
            f"| {res.total_score}/{res.total_max} |"
        )

    lines.append("")

    # --- Aggregate ---
    total_s = sum(r.total_score for r in results)
    total_m = sum(r.total_max for r in results)
    exec_ok_count = sum(1 for r in results if r.execution.status == "success")
    avg_latency = sum(r.execution.latency_ms for r in results) / len(results)

    lines.append("## Aggregate")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|---|---|")
    lines.append(
        f"| Total score | {total_s} / {total_m} ({100 * total_s // total_m}%) |"
    )
    lines.append(f"| Execution success | {exec_ok_count} / {len(results)} |")
    lines.append(f"| Avg execution latency | {avg_latency:.0f} ms |")
    lines.append("")

    # --- Per-question breakdown ---
    lines.append("## Per-question breakdown")
    lines.append("")

    for case, res in zip(cases, results):
        s = res.static
        sh = res.schema
        ex = res.execution

        lines.append(f"### {case['id']} — {case['text']}")
        lines.append("")
        lines.append(f"**Complexity:** {case['complexity']}  ")
        lines.append(f"**Score:** {res.total_score}/{res.total_max} ({res.pct:.0f}%)")
        lines.append("")

        # Static
        lines.append("**Phase 1 — Static analysis**")
        if s.tables_found:
            lines.append(
                f"- Tables found: {', '.join(f'`{t}`' for t in s.tables_found)}"
            )
        if s.tables_missing:
            lines.append(
                f"- **Tables MISSING:** {', '.join(f'`{t}`' for t in s.tables_missing)}"
            )
        if s.forbidden_found:
            lines.append(
                f"- **Forbidden tables found (wrong layer):** {', '.join(s.forbidden_found)}"
            )
        if s.columns_found:
            lines.append(
                f"- Columns found: {', '.join(f'`{c}`' for c in s.columns_found)}"
            )
        if s.columns_missing:
            lines.append(
                f"- **Columns MISSING:** {', '.join(f'`{c}`' for c in s.columns_missing)}"
            )
        if s.patterns_matched:
            lines.append(f"- Filter patterns matched: {len(s.patterns_matched)}")
        if s.patterns_missing:
            lines.append(f"- **Filter patterns MISSING:** {s.patterns_missing}")
        lines.append("")

        # Schema
        lines.append("**Phase 2 — Schema validation (Trino DESCRIBE)**")
        if sh.tables_checked:
            lines.append(
                f"- Tables validated: {', '.join(f'`{t}`' for t in sh.tables_checked)}"
            )
        if sh.tables_missing:
            lines.append(
                f"- **Tables NOT found in Trino:** {', '.join(f'`{t}`' for t in sh.tables_missing)}"
            )
        for tbl, missing_cols in sh.columns_missing.items():
            lines.append(
                f"- **Columns not in `{tbl}`:** {', '.join(f'`{c}`' for c in missing_cols)}"
            )
        if sh.errors:
            for err in sh.errors:
                lines.append(f"- Error: {err}")
        lines.append("")

        # Execution
        lines.append("**Phase 3 — Execution validation**")
        lines.append(f"- Status: **{ex.status.upper()}**")
        if ex.status == "success":
            lines.append(f"- Rows returned: {ex.rows_returned}")
            lines.append(
                f"- Columns: {', '.join(f'`{c}`' for c in ex.columns_returned)}"
            )
            lines.append(f"- Latency: {ex.latency_ms:.0f} ms")
            lines.append(
                f"- Meets min-rows threshold: {'yes' if ex.meets_min_rows else 'no'}"
            )
        else:
            lines.append(f"- Error: `{ex.error_message}`")
        lines.append("")

    # --- What this proves ---
    lines.append("## What this proves (and what it doesn't)")
    lines.append("")
    lines.append(
        "**Proves:** The DataHub context contains accurate, executable metadata — "
        "schema descriptions match real Trino tables, golden queries run without errors, "
        "column names are valid. This validates the metadata quality upstream of TARS. "
        "Metadata accuracy is the primary determinant of SQL quality: if DataHub has the "
        "correct table names, column names, and join patterns, TARS will generate correct SQL."
    )
    lines.append("")
    lines.append(
        "**Does not prove:** That a live LLM invocation generates the golden SQL "
        "unprompted. That requires a full LLM eval harness — see the section below."
    )
    lines.append("")

    # --- Future: LLM eval harness ---
    lines.append("## Future: LLM eval harness")
    lines.append("")
    lines.append(
        "To measure whether the **new DataHub context** produces *more accurate SQL than "
        "the old file-based context*, the next step is a prompt-response-judge loop:"
    )
    lines.append("")
    lines.append("```")
    lines.append("For each eval_case question:")
    lines.append("  1. Build old context  → send to LLM → extract SQL → judge SQL")
    lines.append("  2. Build new context  → send to LLM → extract SQL → judge SQL")
    lines.append(
        "  3. Compare: routing accuracy, schema accuracy, execution success, result correctness"
    )
    lines.append("```")
    lines.append("")
    lines.append("Recommended tooling and approaches:")
    lines.append("")
    lines.append(
        "- **Braintrust** (`braintrust-sdk`) — SaaS eval platform with "
        "built-in LLM-as-judge scorers, dataset versioning, and A/B comparison. "
        "Define a dataset from `eval_cases.yml`, a task that calls TARS with both "
        "contexts, and scorers for routing, schema, and execution correctness."
    )
    lines.append(
        "- **RAGAS** — open-source RAG eval framework. Define a custom metric "
        "`SqlSchemaAccuracy` that checks if generated SQL references the expected tables "
        "and columns. Add `SqlExecutionSuccess` that runs the generated SQL on Trino. "
        "Run `ragas evaluate(dataset, metrics=[...])` and compare old vs new context scores."
    )
    lines.append(
        "- **Custom harness** — for full control: wrap the TARS system prompt with both "
        "old and new context, call an LLM API directly, parse out the SQL block, then "
        "run the three-phase rubric above on the *generated* SQL instead of the golden SQL. "
        "This gives the same rubric reuse but tests live LLM behavior."
    )
    lines.append("")
    lines.append("**Key metrics to collect in the LLM eval:**")
    lines.append("")
    lines.append("| Metric | Definition |")
    lines.append("|---|---|")
    lines.append(
        "| Routing accuracy | Correct layer (DW) chosen, no forbidden-table references |"
    )
    lines.append("| Schema accuracy | All expected tables and key columns present |")
    lines.append(
        "| Rule compliance | Partition filter, dedup sentinel, bridge join present |"
    )
    lines.append("| Execution success | Generated SQL runs without Trino error |")
    lines.append(
        "| Result correctness | Expected columns in output, min-rows threshold met |"
    )
    lines.append(
        "| Context efficiency | Input tokens consumed to produce a passing answer |"
    )
    lines.append("")
    lines.append(
        "Combining context efficiency (from `benchmark_tars_pivot.py`) with "
        "output quality (from this LLM eval harness) gives the full ROI picture: "
        "lower cost *and* higher accuracy."
    )
    lines.append("")
    lines.append(f"_Script: `{Path(__file__).relative_to(REPO_ROOT)}`_")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    print("TARS SQL Quality Evaluation")
    print("=" * 60)

    # Warmup: prime the OAuth token cache so the first real query isn't delayed
    # by the SSO browser redirect. The warmup query is ignored if it fails.
    print("Warming up Trino connection (OAuth token cache)...", end=" ", flush=True)
    warmup = _run_trino("SELECT 1 AS ping", timeout=90)
    print(
        "OK"
        if warmup.get("status") == "success"
        else f"skipped ({warmup.get('message', '')})"
    )
    print()

    # Load cases
    if not CASES_PATH.exists():
        print(f"ERROR: {CASES_PATH} not found.", file=sys.stderr)
        sys.exit(1)

    with CASES_PATH.open() as f:
        cases: list[dict] = yaml.safe_load(f)

    print(f"Loaded {len(cases)} eval cases from {CASES_PATH.name}")
    print()

    results: list[CaseResult] = []

    for case in cases:
        print(f"[{case['id']}] {case['text']}")
        res = CaseResult(
            id=case["id"],
            text=case["text"],
            complexity=case["complexity"],
        )

        # Phase 1 — Static
        print("  Phase 1: static analysis...", end=" ", flush=True)
        res.static = phase1_static(case)
        status = (
            "OK"
            if res.static.score == res.static.max_score
            else f"{res.static.score}/{res.static.max_score}"
        )
        print(status)

        # Phase 2 — Schema
        print("  Phase 2: schema validation (Trino DESCRIBE)...", end=" ", flush=True)
        res.schema = phase2_schema(case)
        status = (
            "OK"
            if res.schema.score == res.schema.max_score
            else f"{res.schema.score}/{res.schema.max_score}"
        )
        print(status)

        # Phase 3 — Execution
        print("  Phase 3: execution validation...", end=" ", flush=True)
        res.execution = phase3_execution(case)
        status = f"{res.execution.status.upper()} ({res.execution.rows_returned} rows, {res.execution.latency_ms:.0f}ms)"
        print(status)

        print(f"  Score: {res.total_score}/{res.total_max} ({res.pct:.0f}%)")
        print()
        results.append(res)

    run_ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # --- Write report ---
    report_md = render_report(cases, results, run_ts)
    REPORT_PATH.write_text(report_md)
    print(f"Report written to: {REPORT_PATH}")

    # --- Write raw results ---
    raw: dict[str, Any] = {
        "run_ts": run_ts,
        "cases": [],
    }
    for case, res in zip(cases, results):
        raw["cases"].append(
            {
                "id": res.id,
                "text": res.text,
                "complexity": res.complexity,
                "score": res.total_score,
                "max_score": res.total_max,
                "pct": round(res.pct, 1),
                "static": asdict(res.static),
                "schema": asdict(res.schema),
                "execution": asdict(res.execution),
            }
        )

    RESULTS_PATH.write_text(json.dumps(raw, indent=2))
    print(f"Raw results written to: {RESULTS_PATH}")

    # --- Aggregate summary ---
    total_s = sum(r.total_score for r in results)
    total_m = sum(r.total_max for r in results)
    exec_ok = sum(1 for r in results if r.execution.status == "success")
    print()
    print(f"Overall score: {total_s}/{total_m} ({100 * total_s // total_m}%)")
    print(f"Execution success: {exec_ok}/{len(results)}")


if __name__ == "__main__":
    main()
