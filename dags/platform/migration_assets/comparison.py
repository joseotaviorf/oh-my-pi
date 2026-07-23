"""Compare Twin (Databricks) and EMR metric JSONs, produce verdicts.

Pure-Python comparison logic used by the migration comparison DAG.
Runs inside the Airflow worker (PythonOperator), no Spark needed.
"""

from __future__ import annotations

import json
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


def read_s3_json(uri: str, s3_client=None) -> Dict[str, Any]:
    bucket, key = split_s3_uri(uri)
    client = s3_client or boto3.client("s3")
    response = client.get_object(Bucket=bucket, Key=key)
    return json.loads(response["Body"].read().decode("utf-8"))


def write_s3_json(uri: str, payload: Dict[str, Any], s3_client=None) -> None:
    bucket, key = split_s3_uri(uri)
    client = s3_client or boto3.client("s3")
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, default=str).encode("utf-8"),
        ContentType="application/json",
    )


def list_s3_jsons(bucket: str, prefix: str, s3_client=None) -> List[str]:
    client = s3_client or boto3.client("s3")
    keys: List[str] = []
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".json"):
                keys.append(obj["Key"])
    return keys
