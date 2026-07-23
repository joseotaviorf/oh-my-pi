"""PySpark job: compare Twin (Databricks) and EMR metric JSONs, produce verdicts.

Reads metric JSON files from S3 for both runtimes, compares count, schema,
null counts, and checksums per table. Writes per-table verdict JSON and
aggregate summary JSON.
"""

from __future__ import annotations

import argparse
import json
import sys
from decimal import Decimal
from typing import Any, Dict, List, Optional, Set, Tuple
from urllib.parse import urlparse

import boto3

TYPE_WIDENING: Dict[str, Set[str]] = {
    "int": {"bigint", "long"},
    "integer": {"bigint", "long"},
    "smallint": {"int", "integer", "bigint", "long"},
    "tinyint": {"smallint", "int", "integer", "bigint", "long"},
    "float": {"double"},
    "real": {"float", "double"},
}

COUNT_TOLERANCE_PCT = 5.0


def _normalize_type(type_name: str) -> str:
    return type_name.lower().replace(" ", "").strip('"')


def _types_compatible(baseline_type: str, emr_type: str) -> Tuple[bool, bool]:
    base = _normalize_type(baseline_type)
    emr = _normalize_type(emr_type)
    if base == emr:
        return True, False
    allowed = TYPE_WIDENING.get(base, set())
    if emr in allowed:
        return True, True
    return False, False


def compare_schema(
    twin_schema: List[List[str]],
    emr_schema: List[List[str]],
) -> Tuple[bool, List[str], bool]:
    issues: List[str] = []
    has_warn = False

    twin_cols = [entry[0] for entry in twin_schema]
    emr_cols = [entry[0] for entry in emr_schema]
    if twin_cols != emr_cols:
        missing = set(twin_cols) - set(emr_cols)
        extra = set(emr_cols) - set(twin_cols)
        if missing:
            issues.append(f"Missing columns on EMR: {sorted(missing)}")
        if extra:
            issues.append(f"Extra columns on EMR: {sorted(extra)}")
        if not missing and not extra:
            issues.append("Column order mismatch")
        return False, issues, False

    emr_type_map = {entry[0]: entry[1] for entry in emr_schema}
    for entry in twin_schema:
        name, base_type = entry[0], entry[1]
        emr_type = emr_type_map[name]
        compatible, warn = _types_compatible(base_type, emr_type)
        if not compatible:
            issues.append(f"Type mismatch for {name}: {base_type} vs {emr_type}")
        elif warn:
            has_warn = True
            issues.append(f"Type widening for {name}: {base_type} -> {emr_type}")

    hard_fails = [
        i for i in issues if "mismatch" in i or "Missing" in i or "Extra" in i
    ]
    return len(hard_fails) == 0, issues, has_warn


def compare_count(twin_count: int, emr_count: int) -> Tuple[float, str]:
    if twin_count == 0 and emr_count == 0:
        return 0.0, "PASS"
    if twin_count == 0:
        return 100.0, "FAIL"
    delta_pct = abs(emr_count - twin_count) / twin_count * 100.0
    if delta_pct > COUNT_TOLERANCE_PCT:
        return delta_pct, "FAIL"
    if delta_pct > 0.1:
        return delta_pct, "WARN"
    return delta_pct, "PASS"


def _parse_decimal(value: Optional[str]) -> Decimal:
    if value is None or value == "":
        return Decimal(0)
    return Decimal(str(value))


def compare_null_counts(
    twin_profile: Dict[str, Any], emr_profile: Dict[str, Any]
) -> Tuple[bool, List[str]]:
    issues: List[str] = []
    twin_cols = twin_profile.get("columns", {})
    emr_cols = emr_profile.get("columns", {})
    for name in sorted(set(twin_cols) | set(emr_cols)):
        twin_null = twin_cols.get(name, {}).get("null_count", 0)
        emr_null = emr_cols.get(name, {}).get("null_count", 0)
        if twin_null != emr_null:
            issues.append(
                f"Null count mismatch for {name}: twin={twin_null}, emr={emr_null}"
            )
    return len(issues) == 0, issues


def compare_checksums(
    twin_profile: Dict[str, Any], emr_profile: Dict[str, Any]
) -> Tuple[bool, List[str], bool]:
    issues: List[str] = []
    has_warn = False
    twin_cols = twin_profile.get("columns", {})
    emr_cols = emr_profile.get("columns", {})

    for name in sorted(set(twin_cols) & set(emr_cols)):
        twin_chk = twin_cols[name].get("checksum")
        emr_chk = emr_cols[name].get("checksum")
        if twin_chk is None or emr_chk is None:
            continue
        if twin_chk == emr_chk:
            continue

        twin_sum = _parse_decimal(twin_cols[name].get("checksum_sum"))
        emr_sum = _parse_decimal(emr_cols[name].get("checksum_sum"))
        if twin_sum == 0 and emr_sum == 0:
            continue
        if twin_sum == 0 or emr_sum == 0:
            issues.append(
                f"Checksum mismatch for {name}: twin={twin_chk}, emr={emr_chk}"
            )
            continue

        delta_pct = float(abs(emr_sum - twin_sum) / max(twin_sum, emr_sum) * 100)
        if delta_pct > 5.0:
            issues.append(f"Checksum mismatch for {name}: delta={delta_pct:.3f}%")
        elif delta_pct > 0.1:
            has_warn = True
            issues.append(f"Checksum drift for {name}: delta={delta_pct:.3f}%")

    hard_fails = [i for i in issues if "mismatch" in i]
    return len(hard_fails) == 0, issues, has_warn


def compare_table(
    twin_metric: Dict[str, Any], emr_metric: Dict[str, Any]
) -> Dict[str, Any]:
    table_name = twin_metric.get("table_name", "unknown")
    run_id = twin_metric.get("run_id", "")

    verdict: Dict[str, Any] = {
        "version": 1,
        "run_id": run_id,
        "table_name": table_name,
        "domain": twin_metric.get("domain", ""),
        "dag_name": twin_metric.get("dag_name", ""),
    }

    if twin_metric.get("error"):
        verdict.update(
            {
                "count_match": False,
                "schema_match": False,
                "schema_issues": [f"Twin error: {twin_metric['error']}"],
                "verdict": "FAIL",
            }
        )
        return verdict

    if emr_metric.get("error"):
        verdict.update(
            {
                "count_match": False,
                "schema_match": False,
                "schema_issues": [f"EMR error: {emr_metric['error']}"],
                "verdict": "FAIL",
            }
        )
        return verdict

    twin_count = twin_metric.get("count", 0)
    emr_count = emr_metric.get("count", 0)
    count_delta_pct, count_status = compare_count(twin_count, emr_count)

    twin_schema = twin_metric.get("schema", [])
    emr_schema = emr_metric.get("schema", [])
    schema_ok, schema_issues, schema_warn = compare_schema(twin_schema, emr_schema)

    statuses = [count_status]
    if not schema_ok:
        statuses.append("FAIL")
    elif schema_warn:
        statuses.append("WARN")
    else:
        statuses.append("PASS")

    profile_issues: List[str] = []
    null_match = True
    checksum_match = True
    twin_profile = twin_metric.get("profile")
    emr_profile = emr_metric.get("profile")
    if twin_profile and emr_profile:
        null_ok, null_issues = compare_null_counts(twin_profile, emr_profile)
        null_match = null_ok
        profile_issues.extend(null_issues)
        if not null_ok:
            statuses.append("FAIL")

        chk_ok, chk_issues, chk_warn = compare_checksums(twin_profile, emr_profile)
        checksum_match = chk_ok
        profile_issues.extend(chk_issues)
        if not chk_ok and not chk_warn:
            statuses.append("FAIL")
        elif chk_warn:
            statuses.append("WARN")

    if "FAIL" in statuses:
        overall = "FAIL"
    elif "WARN" in statuses:
        overall = "WARN"
    else:
        overall = "PASS"

    verdict.update(
        {
            "count_match": count_status != "FAIL",
            "count_twin": twin_count,
            "count_emr": emr_count,
            "count_delta_pct": round(count_delta_pct, 3),
            "schema_match": schema_ok,
            "schema_issues": schema_issues,
            "null_count_match": null_match,
            "checksum_match": checksum_match,
            "profile_issues": profile_issues,
            "verdict": overall,
        }
    )
    return verdict


def split_s3_uri(uri: str) -> Tuple[str, str]:
    parsed = urlparse(uri)
    return parsed.netloc, parsed.path.lstrip("/")


def read_s3_json(uri: str) -> Dict[str, Any]:
    bucket, key = split_s3_uri(uri)
    client = boto3.client("s3")
    response = client.get_object(Bucket=bucket, Key=key)
    return json.loads(response["Body"].read().decode("utf-8"))


def write_s3_json(uri: str, payload: Dict[str, Any]) -> None:
    bucket, key = split_s3_uri(uri)
    client = boto3.client("s3")
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, default=str).encode("utf-8"),
        ContentType="application/json",
    )


def list_s3_jsons(bucket: str, prefix: str) -> List[str]:
    client = boto3.client("s3")
    keys: List[str] = []
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".json"):
                keys.append(obj["Key"])
    return keys


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    parser.add_argument(
        "--run-prefix",
        required=True,
        help="S3 prefix for this run (e.g., emr-migration/runs/<run_id>)",
    )
    parser.add_argument("--domain", required=True)
    parser.add_argument("--dag-name", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument(
        "--tables",
        default=None,
        help="Comma-separated table names to compare (restricts to manifest)",
    )
    args = parser.parse_args()

    twin_prefix = f"{args.run_prefix}/twin/{args.domain}/{args.dag_name}/"
    emr_prefix = f"{args.run_prefix}/emr/{args.domain}/{args.dag_name}/"
    verdict_prefix = f"{args.run_prefix}/verdicts/{args.domain}/{args.dag_name}/"

    twin_keys = list_s3_jsons(args.bucket, twin_prefix)
    emr_keys = list_s3_jsons(args.bucket, emr_prefix)

    twin_by_table: Dict[str, Dict[str, Any]] = {}
    for key in twin_keys:
        metric = read_s3_json(f"s3://{args.bucket}/{key}")
        table_name = metric.get("table_name", key.split("/")[-1].replace(".json", ""))
        twin_by_table[table_name] = metric

    emr_by_table: Dict[str, Dict[str, Any]] = {}
    for key in emr_keys:
        metric = read_s3_json(f"s3://{args.bucket}/{key}")
        table_name = metric.get("table_name", key.split("/")[-1].replace(".json", ""))
        emr_by_table[table_name] = metric

    if args.tables:
        expected_tables = set(args.tables.split(","))
        all_tables = sorted(expected_tables)
    else:
        all_tables = sorted(set(twin_by_table.keys()) | set(emr_by_table.keys()))
    if not all_tables:
        print("ERROR: No metric files found for either runtime. Cannot compare.")
        sys.exit(1)

    verdicts: Dict[str, str] = {}
    passed = warned = failed = 0

    for table_name in all_tables:
        twin_metric = twin_by_table.get(
            table_name,
            {
                "table_name": table_name,
                "error": "Missing twin metric",
                "run_id": args.run_id,
            },
        )
        emr_metric = emr_by_table.get(
            table_name,
            {
                "table_name": table_name,
                "error": "Missing EMR metric",
                "run_id": args.run_id,
            },
        )

        for label, metric in [("twin", twin_metric), ("emr", emr_metric)]:
            metric_run_id = metric.get("run_id", "")
            if metric_run_id and metric_run_id != args.run_id:
                metric["error"] = (
                    f"run_id mismatch: expected {args.run_id}, "
                    f"got {metric_run_id} ({label})"
                )

        verdict = compare_table(twin_metric, emr_metric)
        verdict_uri = f"s3://{args.bucket}/{verdict_prefix}{table_name}.json"
        write_s3_json(verdict_uri, verdict)

        v = verdict["verdict"]
        verdicts[table_name] = v
        if v == "PASS":
            passed += 1
        elif v == "WARN":
            warned += 1
        else:
            failed += 1

    summary = {
        "version": 1,
        "run_id": args.run_id,
        "scope_id": f"{args.domain}__{args.dag_name}",
        "total_tables": len(all_tables),
        "passed": passed,
        "warned": warned,
        "failed": failed,
        "tables": verdicts,
        "overall_verdict": "FAIL" if failed else ("WARN" if warned else "PASS"),
        "pr_gate_eligible": failed == 0,
    }
    summary_uri = f"s3://{args.bucket}/{verdict_prefix}summary.json"
    write_s3_json(summary_uri, summary)


if __name__ == "__main__":
    main()
