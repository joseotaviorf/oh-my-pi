"""
EMR Spark job: read profiling store Delta tables, join documentation owners, judge
empty partitions and stale data, and post GChat alerts (prod only unless force_send).

Republish via CI (upload-dag-packages-spark-jobs-s3-{forno,prod}).
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
from typing import Any

import boto3
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.observability.monitoring.constants import (
    DATA_DOCUMENTATION_BUCKET_CONFIG,
    OBSERVABILITY_DATABASE,
    PARTITION_METRICS_TABLE,
    SLA_EXPECTATIONS_S3_KEY,
    TABLE_METRICS_TABLE,
    UNKNOWN_OWNER,
    UNKNOWN_TEAM,
)
from bietlejuice.observability.monitoring.empty_partition import (
    attach_latest_partition_with_data,
    attach_table_context,
    build_table_metrics_index,
    judge_empty_partitions,
    normalize_partition_key,
)
from bietlejuice.observability.monitoring.gchat_notify import (
    notify_observability_findings,
)
from bietlejuice.observability.monitoring.sla_expectations import (
    load_expectations_from_json,
)
from bietlejuice.observability.monitoring.stale_data import judge_stale_data
from bietlejuice.observability.profiling.delta_metadata_reader import (
    DeltaMetadataReader,
)
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "sweep_empty_partitions"
TABLES_DOCUMENTATION = "datalake_documentation_metrics_clean.tables_documentation"
COLLECTION_DELTA_LOG = "delta_log"
COLLECTION_SPARK_MAX_FALLBACK = "spark_max_fallback"

logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dag_name")
    parser.add_argument("table_name")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("freshness_hours")
    parser.add_argument("dry_run")
    parser.add_argument("force_send")
    parser.add_argument("gchat_webhook_url")
    return parser.parse_args()


def _read_s3_text(bucket: str, key: str) -> str | None:
    try:
        body = boto3.client("s3").get_object(Bucket=bucket, Key=key)["Body"].read()
        return body.decode("utf-8")
    except Exception as error:  # noqa: BLE001 — optional SLA staging file
        logger.warning("Could not read s3://%s/%s: %s", bucket, key, error)
        return None


def _latest_tables_documentation(spark_session):
    doc_df = spark_session.table(TABLES_DOCUMENTATION)
    latest = doc_df.agg(
        F.max(F.make_date(F.col("year"), F.col("month"), F.col("day"))).alias(
            "latest_date"
        )
    ).collect()[0]["latest_date"]
    if latest is None:
        return spark_session.createDataFrame([], doc_df.schema)
    return doc_df.filter(
        F.make_date(F.col("year"), F.col("month"), F.col("day")) == F.lit(latest)
    ).select(
        F.col("database_name"),
        F.col("table_name"),
        F.col("owner"),
        F.col("domain"),
    )


def _spark_row_to_dict(row: Any) -> dict[str, Any]:
    payload = row.asDict(recursive=True)
    payload["partition_key"] = normalize_partition_key(payload.get("partition_key"))
    return payload


def _attach_owner_fields(
    findings: list[dict[str, Any]],
    owner_index: dict[tuple[str, str], tuple[str | None, str | None]],
) -> None:
    for finding in findings:
        key = (finding.get("database") or "", finding.get("table") or "")
        owner, domain = owner_index.get(key, (None, None))
        finding["table_owner"] = owner or UNKNOWN_OWNER
        finding["team_owner"] = domain or UNKNOWN_TEAM


def _profiled_at_cutoff(freshness_hours: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(hours=freshness_hours)


def _apply_environment_filter(df, environment: str):
    if environment in ("prod", "forno"):
        return df.filter(F.col("environment") == environment)
    return df


def _apply_freshness_filter(df, freshness_hours: int):
    cutoff = _profiled_at_cutoff(freshness_hours)
    return df.filter(F.col("profiled_at") >= F.lit(cutoff))


def _collect_rows(df) -> list[dict[str, Any]]:
    return [_spark_row_to_dict(row) for row in df.collect()]


def _load_fresh_metric_rows(
    spark_session,
    metrics_table: str,
    *,
    environment: str,
    freshness_hours: int,
) -> list[dict[str, Any]]:
    df = spark_session.table(f"{OBSERVABILITY_DATABASE}.{metrics_table}")
    df = _apply_environment_filter(df, environment)
    df = _apply_freshness_filter(df, freshness_hours)
    return _collect_rows(df)


def _load_partition_rows_with_data(
    spark_session,
    *,
    environment: str,
    table_keys: set[tuple[str, str]],
) -> list[dict[str, Any]]:
    """Partition metrics with row_count > 0 for alert enrichment (no freshness cap)."""
    if not table_keys:
        return []
    keys_df = spark_session.createDataFrame(
        [{"database": database, "table": table} for database, table in table_keys]
    )
    df = spark_session.table(f"{OBSERVABILITY_DATABASE}.{PARTITION_METRICS_TABLE}")
    df = _apply_environment_filter(df, environment)
    df = df.filter(F.col("row_count") > 0)
    df = df.join(keys_df, on=["database", "table"], how="inner")
    return _collect_rows(df)


def _collect_stale_data_findings(
    reader: DeltaMetadataReader,
    expectations: dict[tuple[str, str], Any],
) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for (database, table), sla in expectations.items():
        for check in sla.stale_data_checks():
            fqtn = f"{database}.{table}"
            try:
                if not reader.is_temporal_column(fqtn, check.column):
                    logger.warning(
                        "Skipping stale_data for %s: column %s missing or not temporal",
                        fqtn,
                        check.column,
                    )
                    continue
                use_fallback = reader.has_deletion_vectors(fqtn)
                collection_method = COLLECTION_DELTA_LOG
                latest_data_at = None
                if not use_fallback:
                    latest_data_at, stats_complete = reader.max_column_from_log(
                        fqtn, check.column
                    )
                    if not stats_complete:
                        use_fallback = True
                if use_fallback:
                    collection_method = COLLECTION_SPARK_MAX_FALLBACK
                    latest_data_at = reader.max_column_fallback(fqtn, check.column)
                finding = judge_stale_data(
                    database=database,
                    table=table,
                    check=check,
                    latest_data_at=latest_data_at,
                    collection_method=collection_method,
                )
                if finding is not None:
                    findings.append(finding)
            except Exception as error:  # noqa: BLE001 — isolate per table/check
                logger.error(
                    "stale_data collection failed for %s column=%s: %s",
                    fqtn,
                    check.column,
                    error,
                )
    return findings


def main() -> None:
    args = _parse_args()
    freshness_hours = int(args.freshness_hours)

    config_service = ConfigurationService(args.dag_name)
    documentation_bucket = config_service.get_config(DATA_DOCUMENTATION_BUCKET_CONFIG)
    sla_text = _read_s3_text(documentation_bucket, SLA_EXPECTATIONS_S3_KEY)
    expectations = load_expectations_from_json(sla_text) if sla_text is not None else {}

    partition_rows = _load_fresh_metric_rows(
        spark,
        PARTITION_METRICS_TABLE,
        environment=args.environment,
        freshness_hours=freshness_hours,
    )
    table_rows = _load_fresh_metric_rows(
        spark,
        TABLE_METRICS_TABLE,
        environment=args.environment,
        freshness_hours=freshness_hours,
    )
    tables_doc_df = _latest_tables_documentation(spark)

    owner_index: dict[tuple[str, str], tuple[str | None, str | None]] = {}
    for row in tables_doc_df.collect():
        database = row["database_name"]
        table = row["table_name"]
        if not database or not table:
            continue
        owner = str(row["owner"]).strip() if row["owner"] else None
        domain = str(row["domain"]).strip() if row["domain"] else None
        owner_index[(str(database), str(table))] = (owner, domain)

    table_index = build_table_metrics_index(table_rows)
    empty_findings = judge_empty_partitions(
        partition_rows,
        expectations=expectations,
        freshness_hours=freshness_hours,
    )
    attach_table_context(empty_findings, table_index)
    finding_tables = {
        (finding.get("database") or "", finding.get("table") or "")
        for finding in empty_findings
    }
    partition_rows_with_data = _load_partition_rows_with_data(
        spark,
        environment=args.environment,
        table_keys=finding_tables,
    )
    attach_latest_partition_with_data(empty_findings, partition_rows_with_data)

    reader = DeltaMetadataReader(spark)
    stale_findings = _collect_stale_data_findings(reader, expectations)
    findings = empty_findings + stale_findings

    for finding in findings:
        finding["environment"] = args.environment
    _attach_owner_fields(findings, owner_index)

    logger.info(
        "Completed sweep with %s finding(s) (%s empty, %s stale) for environment=%s",
        len(findings),
        len(empty_findings),
        len(stale_findings),
        args.environment,
    )

    notify_observability_findings(
        findings,
        environment=args.environment,
        gchat_webhook_url=args.gchat_webhook_url,
        dry_run=args.dry_run,
        force_send=args.force_send,
    )


if __name__ == "__main__":
    main()
