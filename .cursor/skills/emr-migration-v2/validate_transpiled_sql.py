"""Validate transpiled SQL on both Databricks and EMR Spark.

Phase 1 (local): SQLGlot parse check on both dialects — fast, no cluster needed.
Phase 2 (optional): EXPLAIN on a real Databricks all-purpose cluster via Commands API.
Phase 3 (optional): EXPLAIN on a persistent EMR cluster via emr-cli submit-step.

Autofix pipeline:
  1. Deterministic SQLGlot transpile (free, fast)
  2. LLM-driven fix loop via Claude (--fix): sends SQL + errors, validates each
     candidate through SQLGlot + Databricks EXPLAIN, feeds errors back for retry

Reads Databricks conn details from ~/.databrickscfg automatically.

Usage:
  # Local SQLGlot check only:
  uv run --no-project --with sqlglot python \
    .cursor/skills/emr-migration-v2/validate_transpiled_sql.py

  # With LLM autofix:
  ANTHROPIC_API_KEY=sk-ant-... uv run --no-project --with sqlglot,anthropic python \
    .cursor/skills/emr-migration-v2/validate_transpiled_sql.py --fix

  # With Databricks EXPLAIN (auto-reads ~/.databrickscfg):
  uv run --no-project --with sqlglot,requests python \
    .cursor/skills/emr-migration-v2/validate_transpiled_sql.py \
    --databricks-cluster-id 0724-123456-abcdef

  # Full: validate + fix + Databricks EXPLAIN + EMR EXPLAIN:
  ANTHROPIC_API_KEY=sk-ant-... \
  uv run --no-project --with sqlglot,requests,boto3,anthropic python \
    .cursor/skills/emr-migration-v2/validate_transpiled_sql.py \
    --fix --databricks-cluster-id 0724-123456-abcdef --emr-cluster-id j-XXXXX
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Optional

import sqlglot

REPO_ROOT = Path(__file__).resolve().parents[3]
PLATFORM_DAG_DIR = REPO_ROOT / "dags" / "platform"
EMR_CLI_DIR = REPO_ROOT / "packages" / "emr-cli"

S3_SYNTAX_TEST_BUCKET = "artifacts.s3.data.quintoandar.com.br"
S3_SYNTAX_TEST_BASE = "emr/staging/syntax-test"

_TEMPLATE_RE = re.compile(r"\{([a-z_][a-z0-9_]*)\}")

_RANGE_JOIN_RE = re.compile(
    r"/\*\+\s*(?:RANGE_JOIN|SKEW)\s*\([^)]*\)\s*\*/", re.IGNORECASE
)


def _prep_for_parse(sql: str) -> str:
    clean = sql.replace("{{", "").replace("}}", "")

    def _replacer(match: re.Match) -> str:
        return f"__TMPL_{match.group(1).upper()}__"

    return _TEMPLATE_RE.sub(_replacer, clean)


def _validate_dialect(sql: str, dialect: str) -> Optional[str]:
    prepped = _prep_for_parse(sql)
    if not prepped.strip():
        return "Empty SQL"
    try:
        sqlglot.parse(prepped, dialect=dialect)
        return None
    except sqlglot.errors.ParseError as exc:
        return str(exc)


_RESTORE_RE = re.compile(r"__TMPL_([A-Z0-9_]+)__")


def _restore_templates(original: str, transpiled: str) -> str:
    return _RESTORE_RE.sub(lambda m: "{" + m.group(1).lower() + "}", transpiled)


def _try_deterministic_fix(sql: str) -> Optional[str]:
    fixed = _RANGE_JOIN_RE.sub("", sql)

    try:
        parsed = sqlglot.parse(_prep_for_parse(fixed), dialect="databricks")
        if parsed:
            fixed_sql = sqlglot.transpile(
                _prep_for_parse(fixed),
                read="databricks",
                write="spark",
            )[0]
            roundtrip = sqlglot.transpile(fixed_sql, read="spark", write="databricks")[
                0
            ]
            sqlglot.parse(roundtrip, dialect="databricks")
            sqlglot.parse(fixed_sql, dialect="spark")
            return _restore_templates(fixed, fixed_sql)
    except Exception:
        pass

    try:
        fixed_sql = sqlglot.transpile(
            _prep_for_parse(fixed),
            read="spark",
            write="spark",
        )[0]
        sqlglot.parse(fixed_sql, dialect="spark")
        sqlglot.parse(fixed_sql, dialect="databricks")
        return _restore_templates(fixed, fixed_sql)
    except Exception:
        pass

    cast_stripped = re.sub(r"::\s*\w+", "", fixed)
    try:
        sqlglot.parse(_prep_for_parse(cast_stripped), dialect="spark")
        sqlglot.parse(_prep_for_parse(cast_stripped), dialect="databricks")
        return cast_stripped
    except Exception:
        pass

    return None


# ---------------------------------------------------------------------------
# LLM-assisted autofix loop
# ---------------------------------------------------------------------------

_LLM_SYSTEM = """\
You are an expert SQL migration engineer converting Databricks SQL to \
Apache Spark 3.5 (EMR).

Rules:
- Output ONLY the fixed SQL — no explanation, no markdown fences, no commentary.
- Preserve template placeholders like {load_start_date}, {environment}, etc. exactly.
- Preserve {{ and }} Jinja escapes exactly.
- GROUP BY ALL works on Spark 3.5 — do NOT rewrite it.
- Remove Databricks-only optimizer hints (RANGE_JOIN, SKEW).
- Replace Databricks-only functions with Spark 3.5 equivalents when possible.
- Do not change query logic — only fix syntax compatibility.
- Keep the original formatting style (line breaks, indentation).
"""


def _llm_fix_loop(
    sql: str,
    errors: dict[str, Optional[str]],
    max_attempts: int,
    explainer: Optional[DatabricksExplainer] = None,
) -> tuple[Optional[str], int]:
    import anthropic

    client = anthropic.Anthropic()
    messages: list[dict[str, str]] = []

    error_parts = [f"- {k}: {v[:300]}" for k, v in errors.items() if v]
    messages.append(
        {
            "role": "user",
            "content": (
                "Fix this SQL so it parses on both Databricks and Spark 3.5.\n\n"
                "Errors:\n" + "\n".join(error_parts) + f"\n\nSQL:\n{sql}"
            ),
        }
    )

    for attempt in range(1, max_attempts + 1):
        resp = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=4096,
            system=_LLM_SYSTEM,
            messages=messages,
        )
        if not resp.content:
            messages.append({"role": "assistant", "content": "(empty)"})
            messages.append(
                {
                    "role": "user",
                    "content": "Response was empty. Please try again with the corrected SQL.",
                }
            )
            continue
        candidate = resp.content[0].text.strip()
        if candidate.startswith("```"):
            lines = candidate.split("\n")
            lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            candidate = "\n".join(lines)

        s_err = _validate_dialect(candidate, "spark")
        d_err = _validate_dialect(candidate, "databricks")

        dbx_err = None
        if not s_err and not d_err and explainer:
            ok, err = explainer.explain(candidate)
            if not ok:
                dbx_err = err

        if not s_err and not d_err and not dbx_err:
            return candidate, attempt

        if attempt >= max_attempts:
            break

        feedback_parts = []
        if s_err:
            feedback_parts.append(f"- Spark parse error: {s_err[:300]}")
        if d_err:
            feedback_parts.append(f"- Databricks parse error: {d_err[:300]}")
        if dbx_err:
            feedback_parts.append(f"- Databricks EXPLAIN error: {dbx_err[:300]}")

        messages.append({"role": "assistant", "content": candidate})
        messages.append(
            {
                "role": "user",
                "content": (
                    "That SQL still has errors:\n"
                    + "\n".join(feedback_parts)
                    + "\n\nFix these issues. Output ONLY the corrected SQL."
                ),
            }
        )

    return None, max_attempts


# ---------------------------------------------------------------------------
# ~/.databrickscfg reader
# ---------------------------------------------------------------------------


def _read_databrickscfg(
    profile: str = "PROD_NEW",
) -> tuple[Optional[str], Optional[str]]:
    cfg_path = Path.home() / ".databrickscfg"
    if not cfg_path.exists():
        return None, None
    config = configparser.ConfigParser()
    config.read(cfg_path)
    if profile not in config:
        return None, None
    section = config[profile]
    host = section.get("host")
    token = section.get("token")
    return host, token


# ---------------------------------------------------------------------------
# Databricks Commands API
# ---------------------------------------------------------------------------


class DatabricksExplainer:
    def __init__(self, host: str, token: str, cluster_id: str):
        import requests

        self.host = host.rstrip("/")
        self.cluster_id = cluster_id
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {token}"
        self._context_id: Optional[str] = None

    def _ensure_context(self) -> str:
        if self._context_id:
            return self._context_id
        for attempt in range(5):
            resp = self.session.post(
                f"{self.host}/api/1.2/contexts/create",
                json={"clusterId": self.cluster_id, "language": "sql"},
            )
            if resp.status_code == 500 and attempt < 4:
                wait = 10 * (attempt + 1)
                print(
                    f"\n  Databricks context creation returned 500, "
                    f"retrying in {wait}s (cluster may be starting)..."
                )
                time.sleep(wait)
                continue
            resp.raise_for_status()
            self._context_id = resp.json()["id"]
            return self._context_id
        resp.raise_for_status()
        return ""

    def explain(self, sql: str) -> tuple[bool, Optional[str]]:
        ctx = self._ensure_context()
        prepped = _prep_for_parse(sql)
        resp = self.session.post(
            f"{self.host}/api/1.2/commands/execute",
            json={
                "clusterId": self.cluster_id,
                "contextId": ctx,
                "language": "sql",
                "command": f"EXPLAIN {prepped}",
            },
        )
        resp.raise_for_status()
        cmd_id = resp.json()["id"]

        for _ in range(120):
            status_resp = self.session.get(
                f"{self.host}/api/1.2/commands/status",
                params={
                    "clusterId": self.cluster_id,
                    "contextId": ctx,
                    "commandId": cmd_id,
                },
            )
            status_resp.raise_for_status()
            data = status_resp.json()
            state = data.get("status")
            if state == "Finished":
                results = data.get("results", {})
                if results.get("resultType") == "error":
                    return False, results.get("summary", "Unknown error")
                return True, None
            if state in ("Cancelled", "Error"):
                return False, data.get("results", {}).get("summary", f"Command {state}")
            time.sleep(1)

        return False, "Timed out waiting for EXPLAIN"

    def destroy_context(self) -> None:
        if self._context_id:
            self.session.post(
                f"{self.host}/api/1.2/contexts/destroy",
                json={
                    "clusterId": self.cluster_id,
                    "contextId": self._context_id,
                },
            )
            self._context_id = None


# ---------------------------------------------------------------------------
# EMR cluster validation (via emr-cli submit-step)
# ---------------------------------------------------------------------------


def _clear_s3_prefix(bucket: str, prefix: str) -> int:
    import boto3

    s3 = boto3.client("s3")
    paginator = s3.get_paginator("list_objects_v2")
    deleted = 0
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        keys = [{"Key": obj["Key"]} for obj in page.get("Contents", [])]
        if keys:
            s3.delete_objects(Bucket=bucket, Delete={"Objects": keys})
            deleted += len(keys)
    return deleted


def _upload_sql_files_to_s3(sql_files: list[Path], run_prefix: str) -> int:
    import boto3

    s3 = boto3.client("s3")
    sql_prefix = f"{run_prefix}/sql"
    total = len(sql_files)
    count = 0
    for sql_file in sql_files:
        scope_id = sql_file.parents[2].name[len("migration_emr_") :]
        key = f"{sql_prefix}/{scope_id}/{sql_file.name}"
        s3.put_object(
            Bucket=S3_SYNTAX_TEST_BUCKET,
            Key=key,
            Body=sql_file.read_bytes(),
            ContentType="text/plain",
        )
        count += 1
        print(f"\r  Uploading: {count}/{total}", end="", flush=True)
    print()
    return count


def _upload_syntax_test_job(run_prefix: str) -> str:
    import boto3

    s3 = boto3.client("s3")
    job_path = Path(__file__).parent / "spark_jobs" / "syntax_test_job.py"
    key = f"{run_prefix}/syntax_test_job.py"
    s3.put_object(
        Bucket=S3_SYNTAX_TEST_BUCKET,
        Key=key,
        Body=job_path.read_bytes(),
        ContentType="text/x-python",
    )
    return f"s3://{S3_SYNTAX_TEST_BUCKET}/{key}"


def _create_persistent_emr_cluster() -> str:
    print("Creating persistent EMR cluster for syntax validation...")
    result = subprocess.run(
        [
            "uv",
            "run",
            "--directory",
            str(EMR_CLI_DIR),
            "emr-cli",
            "create-cluster",
            "--name",
            "syntax-validation",
        ],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    if result.returncode != 0:
        print(f"ERROR creating EMR cluster:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    for line in result.stdout.splitlines():
        if line.strip().startswith("j-"):
            return line.strip()
        match = re.search(r"(j-[A-Z0-9]+)", line)
        if match:
            return match.group(1)
    print(f"Could not parse cluster ID from output:\n{result.stdout}", file=sys.stderr)
    print(
        "WARNING: a cluster may have been created but its ID could not be parsed. "
        "Check the EMR console and terminate manually if needed.",
        file=sys.stderr,
    )
    sys.exit(1)


def _submit_emr_syntax_step_async(
    cluster_id: str, job_uri: str, run_prefix: str
) -> tuple[subprocess.Popen, Path, Path]:
    """Submit EMR step without waiting — returns (Popen, stdout_path, stderr_path).

    Redirects stdout/stderr to temp files to avoid PIPE buffer deadlock when
    the subprocess produces large output.
    """
    sql_prefix = f"s3://{S3_SYNTAX_TEST_BUCKET}/{run_prefix}/sql/"
    result_uri = f"s3://{S3_SYNTAX_TEST_BUCKET}/{run_prefix}/results.json"

    migration_settings = EMR_CLI_DIR / "config" / "migration-validate.yml"
    env = {**os.environ, "EMR_SETTINGS_FILE": str(migration_settings)}

    stdout_path = REPO_ROOT / ".git" / f"emr_step_stdout_{os.getpid()}.log"
    stderr_path = REPO_ROOT / ".git" / f"emr_step_stderr_{os.getpid()}.log"
    stdout_fh = open(stdout_path, "w")
    stderr_fh = open(stderr_path, "w")

    print(f"Submitting syntax validation step to EMR cluster {cluster_id}...")
    proc = subprocess.Popen(
        [
            "uv",
            "run",
            "--directory",
            str(EMR_CLI_DIR),
            "emr-cli",
            "submit-step",
            "--cluster-id",
            cluster_id,
            "--uri",
            job_uri,
            "--step-name",
            "Validate transpiled SQL syntax",
            "--wait",
            "--follow-logs",
            "--job-args",
            f"--sql-prefix {sql_prefix} --result-uri {result_uri}",
        ],
        stdout=stdout_fh,
        stderr=stderr_fh,
        text=True,
        cwd=str(REPO_ROOT),
        env=env,
    )
    return proc, stdout_path, stderr_path


def _collect_emr_results(
    proc: subprocess.Popen,
    run_prefix: str,
    stdout_path: Optional[Path] = None,
    stderr_path: Optional[Path] = None,
) -> dict[str, Any]:
    """Wait for the EMR step subprocess and read results from S3."""
    result_uri = f"s3://{S3_SYNTAX_TEST_BUCKET}/{run_prefix}/results.json"

    print("\n  Waiting for EMR step to complete...")
    proc.wait()
    stdout = stdout_path.read_text() if stdout_path and stdout_path.exists() else ""
    stderr = stderr_path.read_text() if stderr_path and stderr_path.exists() else ""
    for p in (stdout_path, stderr_path):
        if p and p.exists():
            p.unlink()
    print(stdout[-2000:] if len(stdout) > 2000 else stdout)
    if proc.returncode != 0:
        print(f"EMR step failed:\n{stderr[-2000:]}", file=sys.stderr)
        return {"error": stderr[-500:]}

    import boto3

    s3 = boto3.client("s3")
    bucket, key = result_uri.replace("s3://", "").split("/", 1)
    try:
        resp = s3.get_object(Bucket=bucket, Key=key)
        return json.loads(resp["Body"].read().decode("utf-8"))
    except Exception as exc:
        return {"error": f"Could not read results: {exc}"}


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------


def _find_original_sql(scope_id: str, table_name: str) -> Optional[Path]:
    """Find the original SQL file for a table in the source DAG."""
    parts = scope_id.split("__", 1)
    if len(parts) != 2:
        return None
    domain, dag_name = parts
    dag_queries = REPO_ROOT / "dags" / domain / dag_name / "queries"
    if not dag_queries.exists():
        return None
    for layer_dir in dag_queries.iterdir():
        if not layer_dir.is_dir():
            continue
        candidate = layer_dir / f"{table_name}.sql"
        if candidate.exists():
            return candidate
    return None


def discover_sql_files(
    domain_filter: Optional[str] = None,
    scope_filter: Optional[str] = None,
    transpiled_only: bool = False,
) -> list[Path]:
    scope_ids: Optional[set[str]] = None
    if scope_filter:
        scope_ids = {s.strip().replace("/", "__") for s in scope_filter.split(",")}
    files = []
    skipped = 0
    for d in sorted(PLATFORM_DAG_DIR.iterdir()):
        if not d.name.startswith("migration_emr_"):
            continue
        scope_id = d.name[len("migration_emr_") :]
        if scope_ids and scope_id not in scope_ids:
            continue
        if domain_filter:
            file_domain = scope_id.split("__")[0]
            if file_domain != domain_filter:
                continue
        queries_dir = d / "queries" / "migration"
        if queries_dir.exists():
            for sql_file in sorted(queries_dir.glob("*.sql")):
                if transpiled_only:
                    original = _find_original_sql(scope_id, sql_file.stem)
                    if original and original.read_text() == sql_file.read_text():
                        skipped += 1
                        continue
                files.append(sql_file)
    if transpiled_only and skipped:
        print(f"Skipped {skipped} unchanged files (identical to original)")
    return files


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate transpiled SQL on both Databricks and Spark dialects"
    )
    parser.add_argument("--domain", default=None, help="Filter to a specific domain")
    parser.add_argument(
        "--scope",
        default=None,
        help="Comma-separated domain/dag_name list to validate (e.g. fintech/enrich_velo,agents/enrich_agent)",
    )
    parser.add_argument(
        "--transpiled-only",
        action="store_true",
        help="Only validate files that differ from the original SQL (skip unchanged copies)",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Don't write fixes, just report"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Show all errors")

    dbx_group = parser.add_argument_group("Databricks EXPLAIN validation")
    dbx_group.add_argument(
        "--databricks-cluster-id",
        default=None,
        help="All-purpose cluster ID for Databricks EXPLAIN validation",
    )
    dbx_group.add_argument(
        "--databricks-profile",
        default="PROD_NEW",
        help="Profile in ~/.databrickscfg (default: PROD_NEW)",
    )

    fix_group = parser.add_argument_group("Autofix options")
    fix_group.add_argument(
        "--fix",
        action="store_true",
        help="Enable LLM-driven autofix loop for failing queries "
        "(requires ANTHROPIC_API_KEY env var)",
    )
    fix_group.add_argument(
        "--fix-retries",
        type=int,
        default=3,
        help="Max LLM retry attempts per query (default: 3)",
    )

    emr_group = parser.add_argument_group("EMR EXPLAIN validation")
    emr_group.add_argument(
        "--emr-cluster-id",
        default=None,
        help="Existing persistent EMR cluster ID (j-XXXXX). "
        "If not given with --emr-validate, a new cluster is created.",
    )
    emr_group.add_argument(
        "--emr-validate",
        action="store_true",
        help="Run EXPLAIN validation on EMR cluster (creates one if --emr-cluster-id not set)",
    )

    args = parser.parse_args()

    # --- Databricks setup ---
    explainer: Optional[DatabricksExplainer] = None
    if args.databricks_cluster_id:
        host, token = _read_databrickscfg(args.databricks_profile)
        if not host or not token:
            print(
                f"ERROR: Could not read host/token from ~/.databrickscfg "
                f"[{args.databricks_profile}]",
                file=sys.stderr,
            )
            sys.exit(1)
        explainer = DatabricksExplainer(host, token, args.databricks_cluster_id)
        print(
            f"Databricks EXPLAIN enabled "
            f"(cluster: {args.databricks_cluster_id}, profile: {args.databricks_profile})"
        )

    # --- Discover SQL files ---
    sql_files = discover_sql_files(
        domain_filter=args.domain,
        scope_filter=args.scope,
        transpiled_only=args.transpiled_only,
    )
    print(f"Found {len(sql_files)} transpiled SQL files\n")

    if not sql_files:
        print("No files to validate.")
        sys.exit(0)

    # --- EMR setup (submit async — runs in parallel with Databricks EXPLAIN) ---
    emr_results: Optional[dict[str, Any]] = None
    emr_created_cluster: Optional[str] = None
    emr_run_prefix: Optional[str] = None
    emr_proc: Optional[subprocess.Popen] = None
    emr_stdout_path: Optional[Path] = None
    emr_stderr_path: Optional[Path] = None
    emr_failed = False
    use_emr = args.emr_validate or args.emr_cluster_id
    if use_emr:
        run_id = f"{os.getpid()}_{int(time.time())}"
        emr_run_prefix = f"{S3_SYNTAX_TEST_BASE}/runs/{run_id}"
        print(f"Uploading SQL files to S3 (run {run_id})...")
        uploaded = _upload_sql_files_to_s3(sql_files, emr_run_prefix)
        print(f"  Uploaded {uploaded} SQL files")

        job_uri = _upload_syntax_test_job(emr_run_prefix)
        print(f"  Job URI: {job_uri}")

        cluster_id = args.emr_cluster_id
        if not cluster_id:
            cluster_id = _create_persistent_emr_cluster()
            emr_created_cluster = cluster_id
        print(f"  EMR cluster: {cluster_id}")

        emr_proc, emr_stdout_path, emr_stderr_path = _submit_emr_syntax_step_async(
            cluster_id, job_uri, emr_run_prefix
        )
        print("  EMR step submitted (running in background)")

    # --- Phase 1: local SQLGlot + Databricks EXPLAIN (runs while EMR works) ---
    print("\n--- SQLGlot + Databricks EXPLAIN validation ---\n")

    stats: Counter[str] = Counter()
    failures_by_domain: dict[str, list[dict[str, Any]]] = defaultdict(list)
    fixed_files: list[tuple[Path, str]] = []
    all_results: list[dict[str, Any]] = []

    emr_failures: dict[str, str] = {}
    emr_passed_keys: set[str] = set()

    total_files = len(sql_files)
    try:
        for i, sql_file in enumerate(sql_files):
            print(
                f"\r  SQLGlot+Databricks: {i + 1}/{total_files} | "
                f"pass={stats['pass']} fail={stats['fail']} fixed={stats['fixed']}",
                end="",
                flush=True,
            )

            scope_id = sql_file.parents[2].name[len("migration_emr_") :]
            domain = scope_id.split("__")[0]
            table_name = sql_file.stem

            sql = sql_file.read_text()

            spark_err = _validate_dialect(sql, "spark")
            dbx_err = _validate_dialect(sql, "databricks")

            dbx_explain_err = None
            if explainer and not spark_err and not dbx_err:
                try:
                    ok, err = explainer.explain(sql)
                    if not ok:
                        dbx_explain_err = err
                except Exception as exc:
                    print(
                        f"\n  WARNING: Databricks EXPLAIN unavailable "
                        f"({type(exc).__name__}), continuing without it"
                    )
                    explainer = None

            # EMR results not available yet — skip EMR check in this pass
            emr_explain_err = None

            all_ok = not spark_err and not dbx_err and not dbx_explain_err

            if all_ok:
                stats["pass"] += 1
                all_results.append(
                    {
                        "scope_id": scope_id,
                        "domain": domain,
                        "table": table_name,
                        "status": "pass",
                        "path": str(sql_file.relative_to(REPO_ROOT)),
                    }
                )
                continue

            # --- Autofix pipeline ---
            current_errors = {
                "spark": spark_err,
                "databricks": dbx_err,
                "databricks_explain": dbx_explain_err,
                "emr_explain": emr_explain_err,
            }

            fixed_sql = None
            fix_method = None

            # Step 1: deterministic SQLGlot fix (free, fast)
            if not args.dry_run:
                det = _try_deterministic_fix(sql)
                if det:
                    s = _validate_dialect(det, "spark")
                    d = _validate_dialect(det, "databricks")
                    if not s and not d:
                        de = None
                        if explainer:
                            ok, err = explainer.explain(det)
                            if not ok:
                                de = err
                        if not de:
                            fixed_sql = det
                            fix_method = "deterministic"

            # Step 2: LLM fix loop (if --fix and deterministic failed)
            if not fixed_sql and args.fix and not args.dry_run:
                llm_candidate, llm_attempts = _llm_fix_loop(
                    sql, current_errors, args.fix_retries, explainer
                )
                if llm_candidate:
                    fixed_sql = llm_candidate
                    fix_method = f"llm({llm_attempts})"

            result_entry: dict[str, Any] = {
                "scope_id": scope_id,
                "domain": domain,
                "table": table_name,
                "path": str(sql_file.relative_to(REPO_ROOT)),
            }

            if fixed_sql:
                sql_file.write_text(fixed_sql)
                fixed_files.append((sql_file, fixed_sql))
                stats["fixed"] += 1
                print(
                    f"\n  FIXED [{fix_method}] [{domain}] {table_name}",
                    end="",
                )
                result_entry.update(status="fixed", fix_method=fix_method)
            else:
                stats["fail"] += 1
                result_entry.update(
                    status="fail",
                    spark_error=spark_err,
                    databricks_error=dbx_err,
                    databricks_explain_error=dbx_explain_err,
                    emr_explain_error=emr_explain_err,
                )
                failures_by_domain[domain].append(
                    {
                        "scope_id": scope_id,
                        "table": table_name,
                        "spark_error": spark_err,
                        "databricks_error": dbx_err,
                        "databricks_explain_error": dbx_explain_err,
                        "emr_explain_error": emr_explain_err,
                        "path": str(sql_file.relative_to(REPO_ROOT)),
                    }
                )
                if args.verbose:
                    print(f"  FAIL [{domain}] {table_name}:")
                    if spark_err:
                        print(f"       spark: {spark_err[:150]}")
                    if dbx_err:
                        print(f"       databricks: {dbx_err[:150]}")
                    if dbx_explain_err:
                        print(f"       dbx_explain: {dbx_explain_err[:150]}")
                    if emr_explain_err:
                        print(f"       emr_explain: {emr_explain_err[:150]}")

            all_results.append(result_entry)
        print()  # newline after progress bar
    finally:
        if explainer:
            explainer.destroy_context()

    # --- Collect EMR results (ran in parallel with Databricks EXPLAIN) ---
    if emr_proc and emr_run_prefix:
        emr_results = _collect_emr_results(
            emr_proc, emr_run_prefix, emr_stdout_path, emr_stderr_path
        )
        if "error" not in emr_results:
            emr_pass = emr_results.get("passed", 0)
            emr_fail = emr_results.get("failed", 0)
            print(
                f"  EMR validation: {emr_pass} passed, {emr_fail} failed "
                f"out of {emr_results.get('total', 0)}"
            )
            if isinstance(emr_results.get("results"), list):
                for r in emr_results["results"]:
                    key = f"{r.get('scope_id', '')}_{r.get('table_name', '')}"
                    if r.get("valid"):
                        emr_passed_keys.add(key)
                    else:
                        emr_failures[key] = r.get("error", "Unknown EMR error")

            # Merge EMR failures into results
            emr_demoted = 0
            for entry in all_results:
                emr_key = f"{entry['scope_id']}_{entry['table']}"
                if entry["status"] == "pass" and emr_key in emr_failures:
                    entry["status"] = "fail"
                    entry["emr_explain_error"] = emr_failures[emr_key]
                    stats["pass"] -= 1
                    stats["fail"] += 1
                    emr_demoted += 1
                    domain = entry["domain"]
                    failures_by_domain[domain].append(
                        {
                            "scope_id": entry["scope_id"],
                            "table": entry["table"],
                            "spark_error": None,
                            "databricks_error": None,
                            "databricks_explain_error": None,
                            "emr_explain_error": emr_failures[emr_key],
                            "path": entry["path"],
                        }
                    )
            if emr_demoted:
                print(
                    f"  {emr_demoted} file(s) passed SQLGlot+Databricks but failed EMR"
                )
        else:
            emr_failed = True
            print(
                f"  EMR validation error: {emr_results['error']}",
                file=sys.stderr,
            )

    print(f"\n{'=' * 72}")
    print("VALIDATION SUMMARY")
    print(f"{'=' * 72}")
    total = len(sql_files)
    parts = [
        f"Total: {total}",
        f"PASS: {stats['pass']}",
        f"FIXED: {stats['fixed']}",
    ]
    if stats["fixed_local"]:
        parts.append(f"FIXED (needs EMR recheck): {stats['fixed_local']}")
    parts.append(f"FAIL: {stats['fail']}")
    print(" | ".join(parts))
    if stats["fixed"] and args.dry_run:
        print(f"  ({stats['fixed']} fixes available — run without --dry-run to apply)")

    if failures_by_domain:
        print("\n--- Failures by domain ---")
        for domain in sorted(failures_by_domain):
            items = failures_by_domain[domain]
            print(f"  {domain}: {len(items)} file(s)")
            for item in items[:5]:
                err_type = []
                if item["spark_error"]:
                    err_type.append("spark")
                if item["databricks_error"]:
                    err_type.append("databricks")
                if item["databricks_explain_error"]:
                    err_type.append("dbx_explain")
                if item["emr_explain_error"]:
                    err_type.append("emr_explain")
                print(f"    {item['table']} (fails: {', '.join(err_type)})")
            if len(items) > 5:
                print(f"    ... and {len(items) - 5} more")

        error_patterns: Counter[str] = Counter()
        for items in failures_by_domain.values():
            for item in items:
                for err in [
                    item["spark_error"],
                    item["databricks_error"],
                    item["databricks_explain_error"],
                    item["emr_explain_error"],
                ]:
                    if not err:
                        continue
                    if "Expecting" in err:
                        match = re.search(r"Expecting\s+\w+", err)
                        if match:
                            error_patterns[match.group()] += 1
                    elif "Invalid expression" in err:
                        error_patterns["Invalid expression"] += 1
                    else:
                        first_line = err.split("\n")[0][:80]
                        error_patterns[first_line] += 1

        if error_patterns:
            print("\n--- Top error patterns ---")
            for pattern, count in error_patterns.most_common(10):
                print(f"  {count:5d}  {pattern}")

    print(f"{'=' * 72}")

    report_path = REPO_ROOT / ".git" / "validation_report.json"
    full_report = {
        "total": len(sql_files),
        "pass": stats["pass"],
        "fixed": stats["fixed"],
        "fixed_local": stats["fixed_local"],
        "fail": stats["fail"],
        "dry_run": args.dry_run,
        "results": all_results,
    }
    report_path.write_text(json.dumps(full_report, indent=2))
    print(f"\nFull report: {report_path}")

    if emr_created_cluster:
        print(f"\n  Terminating EMR cluster {emr_created_cluster}...")
        subprocess.run(
            [
                "uv",
                "run",
                "--directory",
                str(EMR_CLI_DIR),
                "emr-cli",
                "terminate",
                "--cluster-id",
                emr_created_cluster,
            ],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
        )

    if emr_run_prefix:
        try:
            cleaned = _clear_s3_prefix(S3_SYNTAX_TEST_BUCKET, emr_run_prefix + "/")
            if cleaned:
                print(f"  Cleaned up {cleaned} S3 objects from run")
        except Exception as exc:
            print(
                f"  WARNING: S3 cleanup failed ({exc}), "
                f"clean manually: aws s3 rm --recursive "
                f"s3://{S3_SYNTAX_TEST_BUCKET}/{emr_run_prefix}/",
                file=sys.stderr,
            )

    if stats["fail"] or stats["fixed_local"] or emr_failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
