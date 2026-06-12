"""Phase 4: run translated SQL on EMR and compare against baselines."""

from __future__ import annotations

import json
import logging
from dataclasses import asdict
from pathlib import Path
from typing import List, Optional, Set

from baseline import (
    TableScopeKey,
    baseline_lookup_key,
    discover_tables,
    format_table_label,
    is_baseline_valid,
    load_baseline_for_table,
    preflight_baselines,
    resolve_pin_dates,
)
from cluster_bootstrap import (
    failover_emr_cluster,
    is_cluster_gone_error,
    is_emr_cluster_reusable,
)
from compare import compare_results
from declaration import format_order_by_clause, resolve_order_by_cols
from emr_runner import (
    VALIDATE_JOB_REL,
    SqlStager,
    ensure_aws_credentials,
    resolve_result_from_output,
    run_emr_cli,
)
from models import EmrTableResult, TableBaseline, ValidationResult
from profile import profile_from_dict
from sql_utils import load_pinned_sql

logger = logging.getLogger(__name__)

SKILL_DIR = Path(__file__).resolve().parent
RESULTS_FILE = SKILL_DIR / "validation_results.json"


class EMRValidation:
    def __init__(
        self,
        emr_cluster_id: str,
        dag_name: str,
        domain: str,
        baselines: List[TableBaseline],
        emr_env: str = "prod",
        staging_uri: Optional[str] = None,
        sample_limit: int = 100,
        skip_sample: bool = True,
        skip_profile: bool = False,
        table_filter: Optional[str] = None,
        git_ref: Optional[str] = None,
        baseline_git_ref: str = "master",
        repo_root: Optional[Path] = None,
        load_start_date: str = "",
        load_end_date: str = "",
        allow_create_emr: bool = True,
        quiet: bool = True,
        fail_fast: bool = True,
        table_allowlist: Optional[Set[TableScopeKey]] = None,
    ):
        self.emr_cluster_id = emr_cluster_id
        self.allow_create_emr = allow_create_emr
        self.dag_name = dag_name
        self.domain = domain
        self.baselines_by_key = {
            baseline_lookup_key(baseline.layer, baseline.table): baseline
            for baseline in baselines
        }
        self.emr_env = emr_env
        self.stager = SqlStager(staging_uri=staging_uri, emr_env=emr_env)
        self.sample_limit = sample_limit
        self.skip_sample = skip_sample
        self.skip_profile = skip_profile
        self.table_filter = table_filter
        self.git_ref = git_ref
        self.baseline_git_ref = baseline_git_ref
        self.repo_root = repo_root
        self.load_start = load_start_date
        self.load_end = load_end_date
        self.quiet = quiet
        self.fail_fast = fail_fast
        self.table_allowlist = table_allowlist
        self.results: List[ValidationResult] = []

    def _ensure_cluster_live(self) -> None:
        reusable, state = is_emr_cluster_reusable(self.emr_cluster_id)
        if reusable:
            return
        self.emr_cluster_id = failover_emr_cluster(
            self.emr_cluster_id,
            emr_env=self.emr_env,
            allow_create=self.allow_create_emr,
        )
        logger.info("Switched to EMR cluster %s (was %s)", self.emr_cluster_id, state)

    def _run_emr_step_once(
        self,
        layer: str,
        table_name: str,
        sql_s3_uri: str,
        result_s3_uri: str,
        order_by: str,
    ) -> EmrTableResult:
        ensure_aws_credentials(self.emr_env)
        table_label = format_table_label(layer, table_name)
        cmd = [
            "submit-step",
            "--cluster-id",
            self.emr_cluster_id,
            "--step-name",
            f"migration-validate-{self.dag_name}-{layer}-{table_name}",
            "--uri",
            VALIDATE_JOB_REL,
            "--job-arg",
            "--sql-s3-uri",
            "--job-arg",
            sql_s3_uri,
            "--job-arg",
            "--result-s3-uri",
            "--job-arg",
            result_s3_uri,
            "--job-arg",
            "--order-by",
            "--job-arg",
            order_by,
            "--job-arg",
            "--sample-limit",
            "--job-arg",
            str(self.sample_limit),
            "--wait",
            "--wait-result",
            "--result-s3-uri",
            result_s3_uri,
            "--deploy-mode",
            "client",
            "--action-on-failure",
            "CONTINUE",
        ]
        if not self.quiet:
            cmd.append("--follow-logs")
        if self.skip_sample:
            cmd.extend(["--job-arg", "--skip-sample"])
        if self.skip_profile:
            cmd.extend(["--job-arg", "--skip-profile"])

        if self.quiet:
            logger.info("Validating %s on EMR cluster %s...", table_label, self.emr_cluster_id)
        else:
            logger.info("Submitting EMR step (logs stream below via emr-cli --follow-logs)")

        returncode, output = run_emr_cli(cmd, emr_env=self.emr_env, quiet=self.quiet)
        payload, error = resolve_result_from_output(
            output,
            returncode=returncode,
            result_s3_uri=result_s3_uri,
            emr_env=self.emr_env,
        )
        if payload is None:
            return EmrTableResult(schema=[], count=0, sample=[], error=error)

        schema = [tuple(item) for item in payload.get("schema", [])]
        return EmrTableResult(
            schema=schema,
            count=int(payload.get("count", 0)),
            sample=payload.get("sample", []),
            profile=profile_from_dict(payload.get("profile")),
            error=payload.get("error") or error,
        )

    def _run_emr_step(
        self,
        layer: str,
        table_name: str,
        sql_s3_uri: str,
        result_s3_uri: str,
        order_by: str,
    ) -> EmrTableResult:
        self._ensure_cluster_live()
        result = self._run_emr_step_once(
            layer, table_name, sql_s3_uri, result_s3_uri, order_by
        )
        if result.error and is_cluster_gone_error(result.error):
            logger.warning("Step failed due to dead cluster — failing over and retrying once")
            self.emr_cluster_id = failover_emr_cluster(
                self.emr_cluster_id,
                emr_env=self.emr_env,
                allow_create=self.allow_create_emr,
            )
            return self._run_emr_step_once(
                layer, table_name, sql_s3_uri, result_s3_uri, order_by
            )
        return result

    def run(self) -> bool:
        logger.info("=" * 70)
        logger.info("EMR PROD Validation")
        logger.info("=" * 70)

        if self.fail_fast:
            _, missing = preflight_baselines(
                self.domain,
                self.dag_name,
                self.load_start,
                self.load_end,
                self.table_filter,
                self.table_allowlist,
                git_ref=self.baseline_git_ref,
                repo_root=self.repo_root,
            )
            if missing:
                raise RuntimeError(
                    "Missing or invalid Databricks baselines for: "
                    + ", ".join(missing)
                    + ". Re-run compare (Phase 2 runs automatically) or fix baseline capture errors."
                )

        tables = discover_tables(
            self.domain,
            self.dag_name,
            self.table_filter,
            repo_root=self.repo_root,
        )
        if self.table_allowlist is not None:
            tables = [
                (table_name, layer)
                for table_name, layer in tables
                if baseline_lookup_key(layer, table_name) in self.table_allowlist
            ]
        for table_name, layer in tables:
            baseline = self.baselines_by_key.get(baseline_lookup_key(layer, table_name))
            if not baseline:
                baseline = load_baseline_for_table(
                    self.domain,
                    self.dag_name,
                    table_name,
                    layer,
                )
            if not baseline or not is_baseline_valid(baseline):
                message = (
                    baseline.error
                    if baseline and baseline.error
                    else "Missing or invalid Databricks baseline"
                )
                logger.error("No valid baseline for %s/%s: %s", layer, table_name, message)
                self.results.append(
                    ValidationResult(
                        table=format_table_label(layer, table_name),
                        baseline_count=baseline.count if baseline else 0,
                        emr_count=0,
                        count_delta_pct=0.0,
                        schema_match=False,
                        schema_issues=[message],
                        sample_match=False,
                        sample_diff_rows=[],
                        status="FAIL",
                        message=message,
                    )
                )
                continue

            try:
                pin_start, pin_end = resolve_pin_dates(
                    baseline,
                    self.load_start,
                    self.load_end,
                )
            except ValueError as exc:
                logger.error("%s", exc)
                self.results.append(
                    ValidationResult(
                        table=format_table_label(layer, table_name),
                        baseline_count=baseline.count,
                        emr_count=0,
                        count_delta_pct=100.0,
                        schema_match=False,
                        schema_issues=[str(exc)],
                        sample_match=False,
                        sample_diff_rows=[],
                        status="FAIL",
                        message=str(exc),
                    )
                )
                continue

            pinned_sql = load_pinned_sql(
                self.domain,
                self.dag_name,
                layer,
                table_name,
                pin_start,
                pin_end,
                git_ref=self.git_ref,
                repo_root=self.repo_root,
            )
            order_by = format_order_by_clause(
                baseline.order_by_cols
                or resolve_order_by_cols(
                    table_name,
                    baseline.schema,
                    self.domain,
                    self.dag_name,
                    self.repo_root,
                )
            )
            sql_s3_uri = self.stager.stage_sql(
                pinned_sql,
                self.domain,
                self.dag_name,
                layer,
                table_name,
            )
            result_s3_uri = self.stager.result_uri_for(
                self.domain,
                self.dag_name,
                layer,
                table_name,
            )
            emr_result = self._run_emr_step(
                layer,
                table_name,
                sql_s3_uri,
                result_s3_uri,
                order_by,
            )
            result = compare_results(
                baseline,
                emr_result,
                skip_sample=self.skip_sample,
                skip_profile=self.skip_profile,
            )
            self.results.append(result)

            if self.quiet:
                logger.info("  %s → %s", format_table_label(layer, table_name), result.status)
            else:
                logger.info("  Baseline count: %s", f"{result.baseline_count:,}")
                logger.info("  EMR count:      %s", f"{result.emr_count:,}")
                logger.info("  Delta:          %.3f%%", result.count_delta_pct)
                logger.info("  Status:         %s", result.status)

        RESULTS_FILE.write_text(
            json.dumps([asdict(result) for result in self.results], indent=2, default=str),
            encoding="utf-8",
        )
        logger.info("Results saved: %s", RESULTS_FILE)

        passed = sum(1 for result in self.results if result.status == "PASS")
        warned = sum(1 for result in self.results if result.status == "WARN")
        failed = sum(1 for result in self.results if result.status == "FAIL")
        logger.info("EMR validation complete: %s PASS, %s WARN, %s FAIL", passed, warned, failed)
        return failed == 0
