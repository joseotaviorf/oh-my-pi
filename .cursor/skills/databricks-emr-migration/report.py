"""Human-readable validation reports for EMR migration compare runs."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from typing import TYPE_CHECKING

from manual_check import MANUAL_CHECK_STATUS
from models import ColumnProfile, TableProfile, ValidationResult
from profile import compare_delta_pct
from failure_classifier import failure_retry_label, is_emr_syntax_failure

if TYPE_CHECKING:
    from emr_runner import SqlStager
    from manifest import RunManifest, ValidationJob

SKILL_DIR = Path(__file__).resolve().parent
REPORTS_ROOT = SKILL_DIR / "reports"


def sample_label(result: ValidationResult) -> str:
    if result.sample_match:
        return "ok"
    if result.sample_warn:
        return "warn"
    if "skipped" in result.message:
        return "skip"
    return "fail"


def profile_label(result: ValidationResult) -> str:
    if "profile=skip" in result.message:
        return "skip"
    if result.profile_match:
        return "ok"
    if result.profile_warn:
        return "warn"
    return "fail"


def null_profile_label(result: ValidationResult) -> str:
    if "profile=skip" in result.message:
        return "skip"
    null_issues = [issue for issue in result.profile_issues if issue.startswith("Null count")]
    if null_issues:
        return "fail"
    return "ok"


def checksum_profile_label(result: ValidationResult) -> str:
    if "profile=skip" in result.message:
        return "skip"
    chk_issues = [issue for issue in result.profile_issues if issue.startswith("Checksum")]
    if not chk_issues:
        return "ok"
    if result.profile_warn:
        return "warn"
    return "fail"


def _truncate_checksum(value: Optional[str]) -> str:
    if not value:
        return "—"
    text = str(value).strip()
    if not text:
        return "—"
    return text[:8]


def _parse_checksum_sum(value: Optional[str]) -> float:
    if value is None or value == "":
        return 0.0
    return float(str(value))


def _column_profile_match_label(
    name: str,
    base_col: Optional[ColumnProfile],
    emr_col: Optional[ColumnProfile],
    *,
    checksum_skipped: bool,
) -> str:
    base_null = base_col.null_count if base_col else 0
    emr_null = emr_col.null_count if emr_col else 0
    if base_null != emr_null:
        return "fail"
    if checksum_skipped:
        return "ok"
    base_hex = base_col.checksum if base_col else None
    emr_hex = emr_col.checksum if emr_col else None
    if base_hex and emr_hex and base_hex == emr_hex:
        return "ok"
    base_sum = _parse_checksum_sum(base_col.checksum_sum if base_col else None)
    emr_sum = _parse_checksum_sum(emr_col.checksum_sum if emr_col else None)
    _, status = compare_delta_pct(Decimal(str(base_sum)), Decimal(str(emr_sum)))
    if status == "PASS":
        return "ok"
    if status == "WARN":
        return "warn"
    return "fail"


def _format_profile_footnotes(profile: TableProfile) -> str:
    lines: List[str] = []
    if profile.skipped_columns:
        cols = ", ".join(f"`{name}`" for name in profile.skipped_columns)
        lines.append(f"_Complex columns skipped (not profiled): {cols}_")
    if profile.truncated_columns:
        cols = ", ".join(f"`{name}`" for name in profile.truncated_columns)
        lines.append(f"_Truncated columns (not profiled): {cols}_")
    if profile.checksum_skipped_columns:
        cols = ", ".join(f"`{name}`" for name in profile.checksum_skipped_columns)
        lines.append(f"_Checksum skipped (null counts only): {cols}_")
    if not lines:
        return ""
    return "\n".join(lines) + "\n\n"


def _format_profile_table(baseline: TableProfile, emr: TableProfile) -> str:
    headers = ["Column", "DB null", "EMR null", "DB chk", "EMR chk", "Match"]
    rows: List[List[str]] = []
    checksum_skip = {name.lower() for name in baseline.checksum_skipped_columns}

    for name in sorted(baseline.columns):
        base_col = baseline.columns.get(name)
        emr_col = emr.columns.get(name)
        is_checksum_skipped = name.lower() in checksum_skip
        if is_checksum_skipped:
            db_chk = "n/a"
            emr_chk = "n/a"
        else:
            db_chk = _truncate_checksum(base_col.checksum if base_col else None)
            emr_chk = _truncate_checksum(emr_col.checksum if emr_col else None)
        rows.append(
            [
                f"`{name}`",
                str(base_col.null_count if base_col else 0),
                str(emr_col.null_count if emr_col else 0),
                db_chk,
                emr_chk,
                _column_profile_match_label(
                    name,
                    base_col,
                    emr_col,
                    checksum_skipped=is_checksum_skipped,
                ),
            ]
        )

    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def _format_profile_section(results: List[ValidationResult]) -> str:
    sections: List[str] = []
    for result in results:
        if result.baseline_profile is None or result.emr_profile is None:
            continue
        if "profile=skip" in result.message:
            continue
        table_block = [
            f"### {result.table}",
            "",
            _format_profile_table(result.baseline_profile, result.emr_profile),
            "",
            _format_profile_footnotes(result.baseline_profile).rstrip(),
        ]
        sections.append("\n".join(line for line in table_block if line is not None).strip())

    if not sections:
        return ""
    return "## Column profile\n\n" + "\n\n".join(sections) + "\n\n"


def verdict_label(status: str) -> str:
    if status == "PASS":
        return "OK"
    if status == "WARN":
        return "WARN"
    if status == MANUAL_CHECK_STATUS:
        return "MANUAL"
    return "NOT OK"


def is_fully_skipped_dag(
    results: List[ValidationResult],
    skipped_tables: Optional[List[str]] = None,
) -> bool:
    """True when compare ran but every table was already EMR-compatible on master."""
    return not results and bool(skipped_tables)


def syntax_failures(results: List[ValidationResult]) -> List[ValidationResult]:
    return [
        result
        for result in results
        if result.status == "FAIL" and is_emr_syntax_failure(result.message)
    ]


def parity_failures(results: List[ValidationResult]) -> List[ValidationResult]:
    return [
        result
        for result in results
        if result.status == "FAIL" and not is_emr_syntax_failure(result.message)
    ]


def watch_has_syntax_failures(
    dag_results: Dict[str, List[ValidationResult]],
) -> bool:
    return any(syntax_failures(results) for results in dag_results.values())


def _migration_status(
    results: List[ValidationResult],
    *,
    fully_skipped: bool = False,
) -> str:
    if fully_skipped:
        return "Skipped"
    _, warned, failed, manual, _ = aggregate_dag_status(results, fully_skipped=fully_skipped)
    if failed:
        return "Blocked"
    if manual:
        return "Held (manual check)"
    if warned:
        return "Migrated (warnings)"
    return "Migrated"


def aggregate_dag_status(
    results: List[ValidationResult],
    *,
    fully_skipped: bool = False,
) -> Tuple[int, int, int, int, bool]:
    if fully_skipped:
        return 0, 0, 0, 0, False
    passed = sum(1 for result in results if result.status == "PASS")
    warned = sum(1 for result in results if result.status == "WARN")
    manual = sum(1 for result in results if result.status == MANUAL_CHECK_STATUS)
    failed = sum(1 for result in results if result.status == "FAIL")
    pr_allowed = failed == 0 and manual == 0
    return passed, warned, failed, manual, pr_allowed


def format_summary_table(results: List[ValidationResult]) -> str:
    headers = ["Table", "DB rows", "EMR rows", "Delta", "Schema", "Null", "Chk", "Sample", "Verdict"]
    rows: List[List[str]] = []
    for result in results:
        schema_label = "ok" if result.schema_match else "fail"
        rows.append(
            [
                result.table,
                f"{result.baseline_count:,}",
                f"{result.emr_count:,}",
                f"{result.count_delta_pct:.1f}%",
                schema_label,
                null_profile_label(result),
                checksum_profile_label(result),
                sample_label(result),
                verdict_label(result.status),
            ]
        )

    widths = [len(header) for header in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    def fmt_row(cells: List[str]) -> str:
        return " | ".join(cell.ljust(widths[index]) for index, cell in enumerate(cells))

    separator = "-+-".join("-" * width for width in widths)
    lines = [fmt_row(headers), separator]
    lines.extend(fmt_row(row) for row in rows)
    return "\n".join(lines)


def format_markdown_table(results: List[ValidationResult]) -> str:
    headers = ["Table", "DB rows", "EMR rows", "Delta", "Schema", "Null", "Chk", "Sample", "Verdict"]
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for result in results:
        schema_label = "ok" if result.schema_match else "fail"
        lines.append(
            "| "
            + " | ".join(
                [
                    result.table,
                    f"{result.baseline_count:,}",
                    f"{result.emr_count:,}",
                    f"{result.count_delta_pct:.1f}%",
                    schema_label,
                    null_profile_label(result),
                    checksum_profile_label(result),
                    sample_label(result),
                    verdict_label(result.status),
                ]
            )
            + " |"
        )
    return "\n".join(lines)


def _format_manual_check(results: List[ValidationResult]) -> str:
    manual = [result for result in results if result.status == MANUAL_CHECK_STATUS]
    if not manual:
        return ""
    sections: List[str] = [
        "## Manual check required",
        "",
        "These tables exceeded the runtime threshold or timed out during baseline capture. "
        "Re-run them individually with a longer timeout before merging:",
        "",
    ]
    for result in manual:
        sections.append(f"- `{result.table}` — {result.message}")
    sections.append("")
    return "\n".join(sections)


def _format_excluded_from_pr(results: List[ValidationResult]) -> str:
    blockers = [result for result in results if result.status == "FAIL"]
    manual = [result for result in results if result.status == MANUAL_CHECK_STATUS]
    if not blockers and not manual:
        return "_DAG is PR-eligible (PASS/WARN only)._"

    sections: List[str] = []
    if manual:
        sections.extend(
            [
                "## Held from PR (manual check)",
                "",
                "One MANUAL table holds the whole DAG from PR until re-validated with a longer timeout.",
                "",
                "| Table | Reason |",
                "|-------|--------|",
            ]
        )
        for result in manual:
            reason = result.message.replace("|", "\\|")
            if len(reason) > 120:
                reason = reason[:117] + "..."
            sections.append(f"| `{result.table}` | {reason} |")
        sections.append("")

    if blockers:
        sections.extend(
            [
                "## Excluded from PR (FAIL)",
                "",
                "One FAIL table excludes the whole DAG from PR.",
                "",
                "| Table | Error | Retry? |",
                "|-------|-------|--------|",
            ]
        )
        for result in blockers:
            error = result.message.replace("|", "\\|")
            if len(error) > 120:
                error = error[:117] + "..."
            sections.append(
                f"| `{result.table}` | {error} | {failure_retry_label(result.message)} |"
            )
        sections.append("")

    return "\n".join(sections)


def _format_blockers(results: List[ValidationResult], max_diff_rows: int = 3) -> str:
    blockers = [result for result in results if result.status == "FAIL"]
    if not blockers:
        return "_No blockers — all tables passed or warned._"

    sections: List[str] = []
    for result in blockers:
        lines = [f"### {result.table}", "", f"- **Message:** {result.message}"]
        if result.schema_issues:
            lines.append("- **Schema issues:**")
            for issue in result.schema_issues:
                lines.append(f"  - {issue}")
        if result.profile_issues:
            lines.append("- **Profile issues (first 5):**")
            for issue in result.profile_issues[:5]:
                lines.append(f"  - {issue}")
        if result.sample_diff_rows:
            lines.append("- **Sample diffs (first rows):**")
            lines.append("```json")
            import json

            lines.append(json.dumps(result.sample_diff_rows[:max_diff_rows], indent=2, default=str))
            lines.append("```")
        sections.append("\n".join(lines))
    return "\n\n".join(sections)


def write_report(
    domain: str,
    dag_name: str,
    results: List[ValidationResult],
    *,
    databricks_cluster_id: str = "",
    emr_cluster_id: str = "",
    load_start_date: str = "",
    load_end_date: str = "",
    report_date: Optional[str] = None,
    skipped_tables: Optional[List[str]] = None,
    fully_skipped: bool = False,
) -> Path:
    report_day = report_date or str(date.today())
    report_dir = REPORTS_ROOT / domain
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / f"{dag_name}_{report_day}.md"

    fully_skipped = fully_skipped or is_fully_skipped_dag(results, skipped_tables)
    passed, warned, failed, manual, pr_allowed = aggregate_dag_status(
        results,
        fully_skipped=fully_skipped,
    )
    if fully_skipped:
        dag_verdict = "Skipped"
    elif pr_allowed:
        if warned:
            dag_verdict = "OK (with warnings)"
        else:
            dag_verdict = "OK"
    elif manual and not failed:
        dag_verdict = "Held (manual check required)"
    else:
        dag_verdict = "NOT OK"

    per_table_section = (
        "_No tables required translation — all SQL files are already EMR-compatible on master._"
        if fully_skipped
        else format_markdown_table(results)
    )
    profile_section = "" if fully_skipped else _format_profile_section(results)

    skipped_section = ""
    if skipped_tables:
        skipped_section = (
            "## Skipped (already EMR-compatible on master)\n\n"
            + ", ".join(f"`{name}`" for name in skipped_tables)
            + "\n\n"
        )

    next_steps = (
        "- No compare run was needed — all tables are EMR-compatible on master."
        if fully_skipped
        else (
            "- Proceed to repo hygiene and PR."
            + (
                " Re-validate manual-check tables before production cutover."
                if manual
                else ""
            )
            if pr_allowed
            else "- Fix failing tables and re-run compare."
        )
    )

    manual_section = _format_manual_check(results)

    content = f"""# EMR Migration Validation — {dag_name}

**Domain:** {domain}  
**Date:** {report_day}  
**Window:** {load_start_date} → {load_end_date}  
**Databricks cluster:** `{databricks_cluster_id or "n/a"}`  
**EMR cluster:** `{emr_cluster_id or "n/a"}`  

## Summary

| Metric | Value |
|--------|-------|
| Tables | {len(results)} |
| OK | {passed} |
| WARN | {warned} |
| Manual check | {manual} |
| NOT OK | {failed} |
| DAG verdict | **{dag_verdict}** |
| PR allowed | **{"Yes" if pr_allowed else "No"}** |

## Per-table results

{per_table_section}

{profile_section}{skipped_section}{manual_section}{_format_excluded_from_pr(results) if not fully_skipped else ""}

## Blockers (detail)

{"_No validation run — nothing to compare._" if fully_skipped else _format_blockers(results)}

## Next steps

{next_steps}
- Full machine-readable results: `.cursor/skills/databricks-emr-migration/validation_results.json`
"""
    report_path.write_text(content, encoding="utf-8")
    return report_path


def update_migration_summary(
    domain: str,
    dag_name: str,
    report_path: Path,
    results: List[ValidationResult],
    *,
    skipped_tables: Optional[List[str]] = None,
    fully_skipped: bool = False,
) -> Path:
    summary_path = REPORTS_ROOT / domain / "MIGRATION_SUMMARY.md"
    summary_path.parent.mkdir(parents=True, exist_ok=True)

    fully_skipped = fully_skipped or is_fully_skipped_dag(results, skipped_tables)
    status = _migration_status(results, fully_skipped=fully_skipped)

    try:
        rel_report = report_path.relative_to(SKILL_DIR)
    except ValueError:
        rel_report = Path("reports") / domain / report_path.name
    row = f"| {dag_name} | {status} | [{report_path.name}]({rel_report.as_posix()}) |"

    if summary_path.exists():
        content = summary_path.read_text(encoding="utf-8")
    else:
        content = (
            f"# EMR Migration Summary — {domain}\n\n"
            "| DAG | Status | Report |\n"
            "|-----|--------|--------|\n"
        )

    dag_marker = f"| {dag_name} |"
    if dag_marker in content:
        lines = content.splitlines()
        content = "\n".join(
            line if not line.startswith(dag_marker) else row for line in lines
        )
    else:
        if not content.endswith("\n"):
            content += "\n"
        content += row + "\n"

    summary_path.write_text(content, encoding="utf-8")
    return summary_path


def _pending_table_lines(pending_jobs: List["ValidationJob"]) -> str:
    if not pending_jobs:
        return "_All tables compared._"
    lines = ["| Table | Status |", "|-------|--------|"]
    for job in pending_jobs:
        lines.append(f"| {job.table_label} | {job.status} |")
    return "\n".join(lines)


def write_partial_report(
    domain: str,
    dag_name: str,
    results: List[ValidationResult],
    *,
    pending_jobs: Optional[List["ValidationJob"]] = None,
    run_id: str = "",
    load_start_date: str = "",
    load_end_date: str = "",
    databricks_cluster_id: str = "",
    emr_cluster_id: str = "",
    skipped_tables: Optional[List[str]] = None,
    stager: Optional["SqlStager"] = None,
    emr_env: str = "prod",
    report_date: Optional[str] = None,
) -> Path:
    """Rewrite markdown report with completed + pending tables (live progress)."""
    report_day = report_date or str(date.today())
    report_dir = REPORTS_ROOT / domain
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / f"{dag_name}_{report_day}.md"

    total = len(results) + len(pending_jobs or [])
    compared = len(results)
    passed, warned, failed, manual, pr_allowed = aggregate_dag_status(results)
    pending_section = _pending_table_lines(pending_jobs or [])

    per_table_section = (
        format_markdown_table(results) if results else "_No tables compared yet._"
    )
    profile_section = _format_profile_section(results) if results else ""
    skipped_section = ""
    if skipped_tables:
        skipped_section = (
            "## Skipped (already EMR-compatible on master)\n\n"
            + ", ".join(f"`{name}`" for name in skipped_tables)
            + "\n\n"
        )

    content = f"""# EMR Migration Validation — {dag_name}

**Domain:** {domain}  
**Date:** {report_day}  
**Run ID:** `{run_id or "n/a"}`  
**Progress:** {compared}/{total} compared  
**Window:** {load_start_date} → {load_end_date}  
**Databricks cluster:** `{databricks_cluster_id or "n/a"}`  
**EMR cluster:** `{emr_cluster_id or "n/a"}`  

## Summary (partial)

| Metric | Value |
|--------|-------|
| Compared | {compared}/{total} |
| OK | {passed} |
| WARN | {warned} |
| Manual check | {manual} |
| NOT OK | {failed} |
| PR allowed (so far) | **{"Yes" if pr_allowed and not pending_jobs else "Pending"}** |

## Per-table results

{per_table_section}

{profile_section}## Pending

{pending_section}

{skipped_section}## Blockers

{_format_blockers(results)}

_Status: validation in progress — report updates as S3 results land._
"""
    report_path.write_text(content, encoding="utf-8")

    if stager is not None:
        from emr_runner import upload_text_to_s3

        s3_uri = stager.report_uri_for(domain, dag_name)
        upload_text_to_s3(s3_uri, content, emr_env=emr_env, content_type="text/markdown")

    return report_path


def finalize_dag_reports(
    domain: str,
    dag_name: str,
    results: List[ValidationResult],
    *,
    run_id: str = "",
    load_start_date: str = "",
    load_end_date: str = "",
    databricks_cluster_id: str = "",
    emr_cluster_id: str = "",
    skipped_tables: Optional[List[str]] = None,
    stager: Optional["SqlStager"] = None,
    emr_env: str = "prod",
) -> Path:
    """Write final report and update MIGRATION_SUMMARY when watch completes."""
    report_path = write_report(
        domain,
        dag_name,
        results,
        databricks_cluster_id=databricks_cluster_id,
        emr_cluster_id=emr_cluster_id,
        load_start_date=load_start_date,
        load_end_date=load_end_date,
        skipped_tables=skipped_tables,
    )
    update_migration_summary(
        domain,
        dag_name,
        report_path,
        results,
        skipped_tables=skipped_tables,
    )
    if stager is not None:
        from emr_runner import upload_text_to_s3

        upload_text_to_s3(
            stager.report_uri_for(domain, dag_name),
            report_path.read_text(encoding="utf-8"),
            emr_env=emr_env,
            content_type="text/markdown",
        )
    return report_path


def print_live_summary(manifest: "RunManifest", *, final: bool = False) -> None:
    counts = manifest.counts()
    compared = counts["compared"]
    total = counts["total"]
    ok = sum(1 for job in manifest.jobs if job.verdict == "PASS")
    warn = sum(1 for job in manifest.jobs if job.verdict == "WARN")
    manual = counts["manual_check"] + counts["timeout"]
    fail = sum(1 for job in manifest.jobs if job.verdict == "FAIL")
    pending = (
        total
        - compared
        - counts["error"]
        - counts["timeout"]
        - counts["manual_check"]
    )
    prefix = "Final" if final else "Progress"
    print(
        f"{prefix} run_id={manifest.run_id}: "
        f"{compared}/{total} compared | {ok} OK | {warn} WARN | {manual} MANUAL | {fail} FAIL | {pending} pending"
    )


def print_compare_summary(
    dag_name: str,
    results: List[ValidationResult],
    report_path: Path,
    skipped_tables: Optional[List[str]] = None,
    *,
    fully_skipped: bool = False,
) -> None:
    fully_skipped = fully_skipped or is_fully_skipped_dag(results, skipped_tables)
    passed, warned, failed, manual, pr_allowed = aggregate_dag_status(
        results,
        fully_skipped=fully_skipped,
    )
    print()
    if results:
        print(format_summary_table(results))
        print()
    if skipped_tables:
        print(f"Skipped (no translation needed): {', '.join(skipped_tables)}")
        print()
    if fully_skipped:
        print(
            f"DAG {dag_name}: all tables EMR-compatible on master — validation skipped"
        )
    elif pr_allowed:
        suffix = ""
        if warned:
            suffix = f", {warned} WARN"
        print(f"DAG {dag_name}: {passed} OK{suffix} — PR allowed")
    elif manual and not failed:
        print(
            f"DAG {dag_name}: {passed} OK, {warned} WARN, {manual} MANUAL — "
            f"PR held (re-validate manual tables first)"
        )
    else:
        print(
            f"DAG {dag_name}: {passed} OK, {warned} WARN, {failed} NOT OK — "
            f"PR blocked ({failed} FAIL)"
        )
    print(f"Report: {report_path}")


def _truncate_error(message: str, limit: int = 80) -> str:
    text = message.replace("\n", " ").strip()
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def print_batch_gate_summary(dag_results: Dict[str, List[ValidationResult]]) -> None:
    """Print PR-eligible vs held vs blocked DAG tables (mandatory end-of-batch deliverable)."""
    eligible_rows: List[List[str]] = []
    held_rows: List[List[str]] = []
    blocked_rows: List[List[str]] = []

    for dag_key in sorted(dag_results.keys()):
        results = dag_results[dag_key]
        passed, warned, failed, manual, pr_allowed = aggregate_dag_status(results)
        if pr_allowed:
            eligible_rows.append(
                [
                    dag_key,
                    str(len(results)),
                    f"{passed} PASS, {warned} WARN",
                    "yes",
                ]
            )
            continue
        if failed:
            for result in results:
                if result.status != "FAIL":
                    continue
                blocked_rows.append(
                    [
                        dag_key,
                        result.table,
                        _truncate_error(result.message),
                        failure_retry_label(result.message),
                    ]
                )
            continue
        for result in results:
            if result.status != MANUAL_CHECK_STATUS:
                continue
            held_rows.append(
                [
                    dag_key,
                    result.table,
                    _truncate_error(result.message),
                ]
            )

    print()
    print("## PR eligible")
    if eligible_rows:
        headers = ["DAG", "Tables", "Verdict summary", "PR allowed"]
        widths = [len(h) for h in headers]
        for row in eligible_rows:
            for index, cell in enumerate(row):
                widths[index] = max(widths[index], len(cell))
        separator = "-+-".join("-" * width for width in widths)

        def fmt_row(cells: List[str]) -> str:
            return " | ".join(cell.ljust(widths[index]) for index, cell in enumerate(cells))

        print(fmt_row(headers))
        print(separator)
        for row in eligible_rows:
            print(fmt_row(row))
    else:
        print("_No PR-eligible DAGs._")

    print()
    print("## Held (manual check — excluded from PR)")
    if held_rows:
        headers = ["DAG", "MANUAL table", "Reason"]
        widths = [len(h) for h in headers]
        for row in held_rows:
            for index, cell in enumerate(row):
                widths[index] = max(widths[index], len(cell))
        separator = "-+-".join("-" * width for width in widths)

        def fmt_held(cells: List[str]) -> str:
            return " | ".join(cell.ljust(widths[index]) for index, cell in enumerate(cells))

        print(fmt_held(headers))
        print(separator)
        for row in held_rows:
            print(fmt_held(row))
    else:
        print("_No DAGs held for manual check._")

    print()
    print("## Blocked (FAIL — excluded from PR)")
    if blocked_rows:
        headers = ["DAG", "FAIL table", "Error", "Retry?"]
        widths = [len(h) for h in headers]
        for row in blocked_rows:
            for index, cell in enumerate(row):
                widths[index] = max(widths[index], len(cell))
        separator = "-+-".join("-" * width for width in widths)

        def fmt_blocked(cells: List[str]) -> str:
            return " | ".join(cell.ljust(widths[index]) for index, cell in enumerate(cells))

        print(fmt_blocked(headers))
        print(separator)
        for row in blocked_rows:
            print(fmt_blocked(row))
    else:
        print("_No blocked DAGs._")
    print()
