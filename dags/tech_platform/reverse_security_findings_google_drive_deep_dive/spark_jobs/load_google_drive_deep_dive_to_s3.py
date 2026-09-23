from __future__ import annotations

import json
import logging
from argparse import ArgumentParser

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.reverse_metastore_mapping import ReverseMetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
    resolve_datalake_write_target,
)
from bietlejuice.base.validation.target_resolver import get_prod_database_name
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.storage_services import S3Service

DAG_NAME = "reverse_security_findings_google_drive_deep_dive"
REVERSE_SCHEMA = "security_findings_google_drive_deep_dive"
REVERSE_TABLE = "google_drive_deep_dive"

JOB_NAME = "load_google_drive_deep_dive_to_s3"

logging.getLogger("py4j").setLevel(logging.INFO)
logger = QuintoAndarLogger(JOB_NAME)

RISK_LEVELS = ["CRITICAL", "HIGH", "MEDIUM", "LOW"]
SHARING_STATES = ["EXTERNAL_GRANTEE", "INTERNAL_ONLY"]
SHARING_STATE_BY_FLAG = {True: "EXTERNAL_GRANTEE", False: "INTERNAL_ONLY"}


def resolve_table_fqn(
    datalake_bucket: str, target_database: str | None, target_table: str | None
) -> str:
    reverse_metastore = ReverseMetastoreMapping(
        bucket=datalake_bucket, source=REVERSE_SCHEMA
    )
    prod_database = get_prod_database_name(
        LayerEnum.REVERSE, REVERSE_SCHEMA, datalake_bucket
    )
    read_database, read_table, _ = resolve_datalake_write_target(
        prod_database=prod_database,
        prod_table=REVERSE_TABLE,
        prod_location=reverse_metastore.get_full_database_path(),
        bucket=datalake_bucket,
        target_database=target_database,
        target_table=target_table,
    )
    return f"{read_database}.{read_table}"


def _empty_mix() -> dict[str, int]:
    return {risk_level: 0 for risk_level in RISK_LEVELS}


def _pivot_by_label(rows: list[dict]) -> list[dict]:
    """
    Pivot flat (label, risk_level, count) rows from the SQL layer into
    {label, count, mix} entries, ordered by count desc then label asc — the SQL
    layer only groups by (label, risk_level); this ordering and the per-label
    total are computed here since Spark's collect_list does not guarantee order.
    """
    by_label: dict[str, dict] = {}
    for item in rows:
        entry = by_label.setdefault(
            item["label"], {"label": item["label"], "count": 0, "mix": _empty_mix()}
        )
        entry["count"] += item["count"]
        entry["mix"][item["risk_level"]] = (
            entry["mix"].get(item["risk_level"], 0) + item["count"]
        )

    return sorted(
        by_label.values(), key=lambda entry: (-entry["count"], entry["label"])
    )


def _riskiest_combinations(rows: list[dict], top_n: int = 8) -> list[dict]:
    combinations = [
        {
            "label": f"{item['pii_type']} · {SHARING_STATE_BY_FLAG[item['has_external']]}",
            "count": item["count"],
        }
        for item in rows
    ]
    combinations.sort(key=lambda item: (-item["count"], item["label"]))
    return combinations[:top_n]


def _exposure_matrix(rows: list[dict]) -> dict:
    cells = {sharing_state: _empty_mix() for sharing_state in SHARING_STATES}
    for item in rows:
        sharing_state = SHARING_STATE_BY_FLAG[item["has_external"]]
        cells[sharing_state][item["risk_level"]] = item["count"]

    return {
        "sharing_states": SHARING_STATES,
        "risk_levels": RISK_LEVELS,
        "cells": cells,
    }


def build_payload(spark_client: SparkClient, table_fqn: str) -> str:
    """
    Reshape the materialized reverse row into the Google Drive deep-dive
    schema_version 1 contract: nest the KPI columns under "kpis", pivot each flat (label,
    risk_level, count) breakdown into {label, count, mix}, format the PII x
    external-grantee combinations and the exposure matrix, and apply the array
    ordering the SQL layer leaves undefined (Spark collect_list does not
    guarantee order).
    """
    df = spark_client.get_records(f"SELECT * FROM {table_fqn}")
    rows = df.collect()

    if not rows:
        raise RuntimeError(f"m=build_payload, table_fqn={table_fqn}, msg=no rows found")

    row = rows[0].asDict(recursive=True)

    total_findings = row["total_findings"]
    exposed_beyond_domain = row["exposed_beyond_domain"]
    exposed_pct = (
        (exposed_beyond_domain / total_findings * 100) if total_findings else 0
    )

    payload = {
        "schema_version": row["schema_version"],
        "as_of": row["as_of"],
        "kpis": {
            "org_units_with_findings": row["org_units_with_findings"],
            "shared_drives_affected": row["shared_drives_affected"],
            "external_users_with_pii_access": row["external_users_with_pii_access"],
            "exposed_beyond_domain": exposed_beyond_domain,
        },
        "exposed_pct_note": (
            f"{exposed_pct:.1f}% of findings have at least one external-domain grantee"
        ),
        "pii_findings_total": row["pii_findings_total"],
        "total_findings": total_findings,
        "by_mime_type": _pivot_by_label(row["by_mime_type"]),
        "top_shared_drives": _pivot_by_label(row["top_shared_drives"]),
        "top_external_users": _pivot_by_label(row["top_external_users"]),
        "top_owners": _pivot_by_label(row["top_owners"]),
        "by_org_unit": _pivot_by_label(row["by_org_unit"]),
        "riskiest_combinations": _riskiest_combinations(row["riskiest_combinations"]),
        "exposure_matrix": _exposure_matrix(row["exposure_matrix"]),
    }

    if not payload["top_owners"]:
        payload["top_owners_note"] = (
            "actor_email is 0% populated in the current snapshot "
            "(shared-drive-only scan scope) -- this panel activates automatically "
            "once file-owner identity is captured, with no query changes needed."
        )

    logger.info(
        f"m=build_payload, msg=Google Drive deep dive built, as_of={payload['as_of']}"
    )

    return json.dumps(payload)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod")
    parser.add_argument("execution_date", help="Execution date in YYYY-MM-DD format")
    add_validation_target_args(parser)
    args = parser.parse_args()

    if is_validation_run(args.target_database_name, args.target_table_name):
        logger.info(f"m={JOB_NAME}, msg=Skipping S3 export in cluster validation mode")
    else:
        config_service = ConfigurationService(DAG_NAME)
        datalake_bucket = config_service.get_config("datalake_bucket")
        spark_client = SparkClient(app_name=JOB_NAME)

        table_fqn = resolve_table_fqn(
            datalake_bucket, args.target_database_name, args.target_table_name
        )

        payload = build_payload(spark_client, table_fqn)

        # Defensive: the job skips the upload if a future environment's conf.yml
        # leaves the bucket unset, rather than failing.
        bucket = config_service.get_config("google_drive_deep_dive_s3_bucket")
        if bucket is None:
            logger.info(
                f"m={JOB_NAME}, msg=no Google Drive deep-dive S3 bucket provisioned "
                "for this environment, skipping upload"
            )
        else:
            s3_key = config_service.get_config("google_drive_deep_dive_s3_key")
            s3_service = S3Service(boto3.resource("s3"))
            destination = f"s3://{bucket}/{s3_key}"
            # Prod key shares the executive summary export's prefix
            # (security_data_gateway/executive_summary/), so the existing
            # IDPLATF-8284 s3:PutObject grant already covers this write.
            s3_service.upload_file(payload, destination)
            logger.info(
                f"m={JOB_NAME}, msg=successful S3 put_object, destination={destination}"
            )
