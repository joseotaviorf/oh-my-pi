"""Fetch migration comparison verdicts from S3 and create a PR per DAG scope.

Reads summary.json for each DAG scope, creates one PR with all transpiled
SQL (both PASS and FAIL tables). The PR title shows the DAG-level verdict
(PASS only when all tables pass). The body marks each table's status.

Usage:
  uv run --no-project --with boto3,pyyaml,sqlglot python \
    .cursor/skills/emr-migration-v2/results.py \
    --scope fintech/enrich_velo \
    --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br

  # Multiple DAGs:
  uv run --no-project --with boto3,pyyaml,sqlglot python \
    .cursor/skills/emr-migration-v2/results.py \
    --scope fintech/enrich_velo,fintech/enrich_docx \
    --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br

  # Dry run (just print verdicts, no branches/PRs):
  uv run --no-project --with boto3,pyyaml,sqlglot python \
    .cursor/skills/emr-migration-v2/results.py \
    --scope fintech/enrich_velo \
    --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br \
    --dry-run
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

import boto3
import sqlglot

REPO_ROOT = Path(__file__).resolve().parents[3]

_TEMPLATE_PARAMS = [
    "load_start_date",
    "load_end_date",
    "environment",
    "bucket",
    "dag_name",
    "schema",
    "table_name",
    "partitions",
]

_TEMPLATE_PARAM_RE = re.compile(
    r"\{(" + "|".join(re.escape(p) for p in _TEMPLATE_PARAMS) + r")\}"
)

_LITERAL_DEFAULTS = {
    "load_start_date": "'2026-01-01'",
    "load_end_date": "'2026-01-02'",
    "environment": "'prod'",
    "bucket": "'s3://test-bucket'",
    "dag_name": "'test_dag'",
    "schema": "'test_schema'",
    "table_name": "'test_table'",
    "partitions": "'year=2026/month=01/day=01'",
}


def _validate_spark_syntax(sql: str) -> Optional[str]:
    clean = sql.replace("{{", "").replace("}}", "")

    def _replacer(match: re.Match) -> str:
        return _LITERAL_DEFAULTS.get(match.group(1), "'placeholder'")

    clean = _TEMPLATE_PARAM_RE.sub(_replacer, clean)
    if not clean.strip():
        return None
    try:
        sqlglot.parse(clean, dialect="spark")
        return None
    except sqlglot.errors.ParseError as exc:
        return str(exc)


class GitError(Exception):
    pass


@dataclass
class TableVerdict:
    scope_domain: str
    scope_dag_name: str
    table_name: str
    verdict: str
    count_match: Optional[bool] = None
    count_twin: Optional[int] = None
    count_emr: Optional[int] = None
    count_delta_pct: Optional[float] = None
    schema_match: Optional[bool] = None
    schema_issues: List[str] = field(default_factory=list)
    null_count_match: Optional[bool] = None
    checksum_match: Optional[bool] = None
    profile_issues: List[str] = field(default_factory=list)
    run_id: str = ""
    syntax_error: Optional[str] = None

    @property
    def scope_id(self) -> str:
        return f"{self.scope_domain}__{self.scope_dag_name}"


def _split_s3_uri(uri: str) -> Tuple[str, str]:
    parsed = urlparse(uri)
    return parsed.netloc, parsed.path.lstrip("/")


def _get_s3_client(assume_role_arn: Optional[str] = None):
    if not assume_role_arn:
        return boto3.client("s3")
    sts = boto3.client("sts")
    creds = sts.assume_role(
        RoleArn=assume_role_arn,
        RoleSessionName="migration-results",
        DurationSeconds=3600,
    )["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    ).client("s3")


def _read_s3_json(s3_client, bucket: str, key: str) -> Dict[str, Any]:
    response = s3_client.get_object(Bucket=bucket, Key=key)
    return json.loads(response["Body"].read().decode("utf-8"))


def _find_layer(domain: str, dag_name: str, table_name: str) -> Optional[str]:
    queries_dir = REPO_ROOT / "dags" / domain / dag_name / "queries"
    if not queries_dir.exists():
        return None
    for layer_dir in queries_dir.iterdir():
        if not layer_dir.is_dir():
            continue
        if (layer_dir / f"{table_name}.sql").exists():
            return layer_dir.name
    return None


def _git(*args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        msg = f"git {' '.join(args)} failed: {result.stderr.strip()}"
        if check:
            raise GitError(msg)
        print(msg, file=sys.stderr)
    return result.stdout.strip()


def _gh(*args: str) -> str:
    result = subprocess.run(
        ["gh", *args],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise GitError(f"gh {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def fetch_verdicts(
    scopes: List[Tuple[str, str]],
    artifacts_bucket: str,
    s3_client,
) -> Tuple[List[TableVerdict], List[str]]:
    """Returns (verdicts, skipped_scope_labels)."""
    bucket, bucket_prefix = _split_s3_uri(artifacts_bucket)
    all_verdicts: List[TableVerdict] = []
    skipped: List[str] = []

    for domain, dag_name in scopes:
        scope_id = f"{domain}__{dag_name}"
        scope_label = f"{domain}/{dag_name}"
        compare_dir = REPO_ROOT / "dags" / "platform" / f"migration_compare_{scope_id}"
        manifest_path = compare_dir / "manifest.json"
        if not manifest_path.exists():
            print(
                f"WARNING: no manifest for {scope_label} at {manifest_path}",
                file=sys.stderr,
            )
            skipped.append(scope_label)
            continue

        try:
            manifest = json.loads(manifest_path.read_text())
            run_id = manifest["run_id"]
        except (json.JSONDecodeError, KeyError) as exc:
            print(
                f"WARNING: invalid manifest for {scope_label}: {exc}",
                file=sys.stderr,
            )
            skipped.append(scope_label)
            continue

        summary_key = (
            f"emr-migration/runs/{run_id}/verdicts/{domain}/{dag_name}/summary.json"
        )
        if bucket_prefix:
            summary_key = f"{bucket_prefix}/{summary_key}"

        try:
            summary = _read_s3_json(s3_client, bucket, summary_key)
        except Exception as exc:
            print(
                f"WARNING: failed to read summary for {scope_label}: {exc}",
                file=sys.stderr,
            )
            skipped.append(scope_label)
            continue

        table_verdicts = summary.get("tables", {})

        for table_name in manifest.get("tables", []):
            verdict_str = table_verdicts.get(table_name, "UNKNOWN")

            verdict_detail: Dict[str, Any] = {}
            verdict_key = f"emr-migration/runs/{run_id}/verdicts/{domain}/{dag_name}/{table_name}.json"
            if bucket_prefix:
                verdict_key = f"{bucket_prefix}/{verdict_key}"
            try:
                verdict_detail = _read_s3_json(s3_client, bucket, verdict_key)
            except Exception:
                pass

            transpiled_sql_path = (
                REPO_ROOT
                / "dags"
                / "platform"
                / f"migration_emr_{scope_id}"
                / "queries"
                / "migration"
                / f"{table_name}.sql"
            )
            syntax_err = None
            if transpiled_sql_path.exists():
                syntax_err = _validate_spark_syntax(transpiled_sql_path.read_text())

            all_verdicts.append(
                TableVerdict(
                    scope_domain=domain,
                    scope_dag_name=dag_name,
                    table_name=table_name,
                    verdict=verdict_str,
                    count_match=verdict_detail.get("count_match"),
                    count_twin=verdict_detail.get("count_twin"),
                    count_emr=verdict_detail.get("count_emr"),
                    count_delta_pct=verdict_detail.get("count_delta_pct"),
                    schema_match=verdict_detail.get("schema_match"),
                    schema_issues=verdict_detail.get("schema_issues", []),
                    null_count_match=verdict_detail.get("null_count_match"),
                    checksum_match=verdict_detail.get("checksum_match"),
                    profile_issues=verdict_detail.get("profile_issues", []),
                    run_id=run_id,
                    syntax_error=syntax_err,
                )
            )

    return all_verdicts, skipped


def _dag_verdict(verdicts: List[TableVerdict]) -> str:
    if any(v.syntax_error for v in verdicts):
        return "FAIL"
    if any(v.verdict == "FAIL" for v in verdicts):
        return "FAIL"
    if any(v.verdict not in ("PASS", "WARN") for v in verdicts):
        return "FAIL"
    if any(v.verdict == "WARN" for v in verdicts):
        return "WARN"
    return "PASS"


def print_report(verdicts: List[TableVerdict]) -> None:
    print(f"\n{'=' * 72}")
    print("MIGRATION VALIDATION RESULTS")
    print(f"{'=' * 72}")

    by_scope: Dict[str, List[TableVerdict]] = {}
    for v in verdicts:
        key = f"{v.scope_domain}/{v.scope_dag_name}"
        by_scope.setdefault(key, []).append(v)

    pass_count = sum(1 for v in verdicts if v.verdict == "PASS")
    warn_count = sum(1 for v in verdicts if v.verdict == "WARN")
    fail_count = sum(1 for v in verdicts if v.verdict == "FAIL")
    print(
        f"Total: {len(verdicts)} tables | "
        f"PASS: {pass_count} | WARN: {warn_count} | FAIL: {fail_count}"
    )

    for scope_key, scope_verdicts in sorted(by_scope.items()):
        dag_v = _dag_verdict(scope_verdicts)
        print(f"\n  {scope_key} [{dag_v}]:")
        for v in scope_verdicts:
            icon = {"PASS": "+", "WARN": "~", "FAIL": "!"}
            status = icon.get(v.verdict, "?")
            extras = []
            if v.syntax_error:
                extras.append("SYNTAX ERROR")
            if v.count_delta_pct is not None and v.count_delta_pct > 0:
                extras.append(f"count delta={v.count_delta_pct:.1f}%")
            if v.schema_match is False:
                extras.append("schema mismatch")
            if v.null_count_match is False:
                extras.append("null count mismatch")
            if v.checksum_match is False:
                extras.append("checksum mismatch")
            extra_str = f" ({', '.join(extras)})" if extras else ""
            print(f"    [{status}] {v.table_name}: {v.verdict}{extra_str}")

    print(f"{'=' * 72}\n")


def _build_pr_body(
    verdicts: List[TableVerdict],
    artifacts_bucket: str,
) -> str:
    bucket_host, bucket_prefix = _split_s3_uri(artifacts_bucket)

    by_scope: Dict[str, List[TableVerdict]] = {}
    for v in verdicts:
        key = f"{v.scope_domain}/{v.scope_dag_name}"
        by_scope.setdefault(key, []).append(v)

    pass_count = sum(1 for v in verdicts if v.verdict == "PASS")
    warn_count = sum(1 for v in verdicts if v.verdict == "WARN")
    fail_count = sum(1 for v in verdicts if v.verdict == "FAIL")

    lines: List[str] = []
    lines.append("## Summary\n")
    lines.append(
        "Transpiled SQL queries from Databricks to EMR Spark. "
        "Each table's validation verdict is shown below.\n"
    )

    lines.append(
        f"**{len(verdicts)} tables** | "
        f"PASS: {pass_count} | WARN: {warn_count} | FAIL: {fail_count}\n"
    )

    for scope_key, scope_verdicts in sorted(by_scope.items()):
        dag_v = _dag_verdict(scope_verdicts)
        lines.append(f"- **{scope_key}**: {dag_v}")
    lines.append("")

    if fail_count > 0:
        lines.append(
            "> **Note:** some tables did not pass validation. "
            "The transpiled SQL is included as a recommendation — "
            "review the failing tables before merging.\n"
        )

    syntax_errors = [v for v in verdicts if v.syntax_error]
    if syntax_errors:
        lines.append("## Syntax errors\n")
        lines.append(
            "The following transpiled queries have syntax errors "
            "and need manual fixes:\n"
        )
        for v in sorted(
            syntax_errors,
            key=lambda x: (x.scope_domain, x.scope_dag_name, x.table_name),
        ):
            lines.append(f"### {v.scope_domain}/{v.scope_dag_name} — {v.table_name}\n")
            lines.append(f"```\n{v.syntax_error}\n```\n")

    lines.append("## Validation results\n")
    lines.append(
        "| DAG | Table | Verdict | Syntax | Count (Databricks) | Count (EMR) "
        "| Delta | Schema | Nulls | Checksums |"
    )
    lines.append(
        "|-----|-------|---------|--------|-------------------|------------|"
        "-------|--------|-------|-----------|"
    )

    for v in sorted(
        verdicts, key=lambda x: (x.scope_domain, x.scope_dag_name, x.table_name)
    ):
        syntax_icon = "ERROR" if v.syntax_error else "OK"
        schema_icon = (
            "N/A" if v.schema_match is None else ("OK" if v.schema_match else "FAIL")
        )
        null_icon = (
            "N/A"
            if v.null_count_match is None
            else ("OK" if v.null_count_match else "FAIL")
        )
        chk_icon = (
            "N/A"
            if v.checksum_match is None
            else ("OK" if v.checksum_match else "FAIL")
        )
        dbx_str = f"{v.count_twin:,}" if v.count_twin is not None else "N/A"
        emr_str = f"{v.count_emr:,}" if v.count_emr is not None else "N/A"
        if v.count_delta_pct is not None and v.count_delta_pct > 0:
            delta_str = f"{v.count_delta_pct:.1f}%"
        elif v.count_twin is not None and v.count_emr is not None:
            delta_str = "0%"
        else:
            delta_str = "N/A"
        lines.append(
            f"| {v.scope_domain}/{v.scope_dag_name} | {v.table_name} | "
            f"{v.verdict} | {syntax_icon} | {dbx_str} | {emr_str} | "
            f"{delta_str} | {schema_icon} | {null_icon} | {chk_icon} |"
        )

    fail_verdicts = [v for v in verdicts if v.verdict == "FAIL"]
    if fail_verdicts:
        lines.append("\n## Issues to investigate\n")
        for v in fail_verdicts:
            issues = v.schema_issues + v.profile_issues
            if issues:
                lines.append(
                    f"### {v.scope_domain}/{v.scope_dag_name} — {v.table_name}\n"
                )
                for issue in issues:
                    lines.append(f"- {issue}")
                lines.append("")

    run_ids = sorted(set(v.run_id for v in verdicts))
    if run_ids:
        lines.append("\n## S3 validation artifacts\n")
        for run_id in run_ids:
            run_verdicts = [v for v in verdicts if v.run_id == run_id]
            scopes_in_run = sorted(
                set((v.scope_domain, v.scope_dag_name) for v in run_verdicts)
            )
            lines.append(f"**Run ID**: `{run_id}`\n")
            for domain, dag_name in scopes_in_run:
                s3_prefix = f"emr-migration/runs/{run_id}"
                if bucket_prefix:
                    s3_prefix = f"{bucket_prefix}/{s3_prefix}"
                lines.append(f"- `{domain}/{dag_name}`:")
                lines.append(
                    f"  - Summary: `s3://{bucket_host}/{s3_prefix}/verdicts/{domain}/{dag_name}/summary.json`"
                )
                lines.append(
                    f"  - Databricks metrics: `s3://{bucket_host}/{s3_prefix}/twin/{domain}/{dag_name}/`"
                )
                lines.append(
                    f"  - EMR metrics: `s3://{bucket_host}/{s3_prefix}/emr/{domain}/{dag_name}/`"
                )
                lines.append(
                    f"  - Verdicts: `s3://{bucket_host}/{s3_prefix}/verdicts/{domain}/{dag_name}/`"
                )

    lines.append("\n---\nGenerated by `emr-migration-v2` skill (`results` command)")
    return "\n".join(lines)


def _copy_transpiled_sql(verdicts: List[TableVerdict]) -> List[str]:
    copied: List[str] = []
    for v in verdicts:
        transpiled_path = (
            REPO_ROOT
            / "dags"
            / "platform"
            / f"migration_emr_{v.scope_id}"
            / "queries"
            / "migration"
            / f"{v.table_name}.sql"
        )
        if not transpiled_path.exists():
            print(
                f"WARNING: transpiled SQL not found: {transpiled_path}",
                file=sys.stderr,
            )
            continue

        layer = _find_layer(v.scope_domain, v.scope_dag_name, v.table_name)
        if layer is None:
            print(
                f"WARNING: no query layer found for "
                f"{v.scope_domain}/{v.scope_dag_name}/{v.table_name}, skipping",
                file=sys.stderr,
            )
            continue

        target_dir = (
            REPO_ROOT / "dags" / v.scope_domain / v.scope_dag_name / "queries" / layer
        )
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / f"{v.table_name}.sql"
        shutil.copy2(str(transpiled_path), str(target_path))
        rel_path = str(target_path.relative_to(REPO_ROOT))
        copied.append(rel_path)

    return copied


def _scope_label(scopes: List[Tuple[str, str]]) -> str:
    if len(scopes) == 1:
        return f"{scopes[0][0]}/{scopes[0][1]}"
    domains = sorted(set(d for d, _ in scopes))
    if len(domains) == 1:
        dag_names = sorted(n for _, n in scopes)
        return f"{domains[0]}/{','.join(dag_names)}"
    return ",".join(f"{d}/{n}" for d, n in sorted(scopes))


def _branch_slug(scopes: List[Tuple[str, str]]) -> str:
    if len(scopes) == 1:
        return f"{scopes[0][0]}-{scopes[0][1]}"
    return "-".join(f"{d}-{n}" for d, n in sorted(scopes))[:60]


def create_pr(
    verdicts: List[TableVerdict],
    artifacts_bucket: str,
) -> Optional[str]:
    if not verdicts:
        return None

    scopes = sorted(set((v.scope_domain, v.scope_dag_name) for v in verdicts))
    slug = _branch_slug(scopes)
    label = _scope_label(scopes)
    dag_v = _dag_verdict(verdicts)

    branch_name = f"emr-migration/transpile/{slug}"

    _git("fetch", "origin", "master")
    current_branch = _git("branch", "--show-current")

    stash_result = _git("stash", "-u", check=False)
    created_stash = "No local changes to save" not in stash_result

    try:
        if current_branch == branch_name:
            _git("checkout", "master", check=False)
            current_branch = "master"

        existing = _git("branch", "--list", branch_name, check=False).strip()
        if existing:
            _git("branch", "-D", branch_name)
        _git("checkout", "-b", branch_name, "origin/master")

        copied = _copy_transpiled_sql(verdicts)
        if not copied:
            print("No files copied for PR, skipping", file=sys.stderr)
            return None

        for f in copied:
            _git("add", f)

        commit_msg = f"feat(emr-migration): transpiled queries for {label} [{dag_v}]"
        _git("commit", "-m", commit_msg)

        pr_title = f"feat(emr-migration): transpiled queries for {label} [{dag_v}]"
        body = _build_pr_body(verdicts, artifacts_bucket)
        body_file = REPO_ROOT / ".git" / "pr_body.md"
        body_file.write_text(body, encoding="utf-8")

        _git("push", "-u", "--force-with-lease", "origin", branch_name)

        try:
            pr_url = _gh(
                "pr",
                "create",
                "--title",
                pr_title,
                "--body-file",
                str(body_file),
            )
        except GitError:
            _gh(
                "pr",
                "edit",
                branch_name,
                "--title",
                pr_title,
                "--body-file",
                str(body_file),
            )
            pr_url = _gh("pr", "view", branch_name, "--json", "url", "-q", ".url")

        body_file.unlink(missing_ok=True)
        return pr_url

    finally:
        _git("checkout", current_branch, check=False)
        if created_stash:
            _git("stash", "pop", check=False)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch migration verdicts from S3 and create a PR"
    )
    parser.add_argument(
        "--scope",
        required=True,
        help="Comma-separated domain/dag_name list",
    )
    parser.add_argument(
        "--artifacts-bucket",
        required=True,
        help="S3 URI for artifacts (e.g., s3://artifacts.s3.data.quintoandar.com.br)",
    )
    parser.add_argument(
        "--assume-role-arn",
        default=None,
        help="ARN to assume for S3 access",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print verdicts without creating branches or PRs",
    )
    args = parser.parse_args()

    seen = set()
    scopes: List[Tuple[str, str]] = []
    for spec in args.scope.split(","):
        parts = spec.strip().split("/")
        if len(parts) != 2:
            print(f"Invalid scope: {spec}", file=sys.stderr)
            sys.exit(1)
        key = (parts[0], parts[1])
        if key not in seen:
            seen.add(key)
            scopes.append(key)

    s3_client = _get_s3_client(args.assume_role_arn)
    verdicts, skipped_scopes = fetch_verdicts(scopes, args.artifacts_bucket, s3_client)

    if skipped_scopes:
        print(
            f"WARNING: skipped {len(skipped_scopes)} scope(s): "
            f"{', '.join(skipped_scopes)}",
            file=sys.stderr,
        )

    if not verdicts:
        print("No verdicts found. Have the comparison DAGs run?")
        sys.exit(1)

    print_report(verdicts)

    if args.dry_run:
        dag_v = _dag_verdict(verdicts)
        print(f"Dry run: {len(verdicts)} tables, DAG verdict: {dag_v}")
        sys.exit(0)

    errors = 0

    print(f"\nCreating PR ({len(verdicts)} tables)...")
    try:
        url = create_pr(verdicts, args.artifacts_bucket)
        if url:
            print(f"  PR: {url}")
        else:
            print("  WARNING: no PR created", file=sys.stderr)
            errors += 1
    except GitError as exc:
        print(f"  ERROR creating PR: {exc}", file=sys.stderr)
        errors += 1

    if skipped_scopes:
        errors += 1

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
