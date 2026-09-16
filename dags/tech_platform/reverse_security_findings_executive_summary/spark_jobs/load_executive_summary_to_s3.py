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

DAG_NAME = "reverse_security_findings_executive_summary"
REVERSE_SCHEMA = "security_findings_executive_summary"
REVERSE_TABLE = "executive_summary"

JOB_NAME = "load_executive_summary_to_s3"

logging.getLogger("py4j").setLevel(logging.INFO)
logger = QuintoAndarLogger(JOB_NAME)

RISK_LEVEL_RANK = {"CRITICAL": 1, "HIGH": 2, "MEDIUM": 3, "LOW": 4}


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


def build_payload(spark_client: SparkClient, table_fqn: str) -> str:
    """
    Reshape the materialized reverse row into the schema_version 1 contract from
    IDPLATF-8282: nest the KPI columns under "kpis", rename "dt" to "date" in
    classified_by_day, and apply the array ordering the SQL layer leaves undefined
    (Spark collect_list does not guarantee order).
    """
    df = spark_client.get_records(f"SELECT * FROM {table_fqn}")
    rows = df.collect()

    if not rows:
        raise RuntimeError(f"m=build_payload, table_fqn={table_fqn}, msg=no rows found")

    row = rows[0].asDict(recursive=True)

    payload = {
        "schema_version": row["schema_version"],
        "as_of": row["as_of"],
        "grain": row["grain"],
        "kpis": {
            "total": row["total"],
            "critical": row["critical"],
            "high_plus_critical": row["high_plus_critical"],
            "classified_last_30d": row["classified_last_30d"],
        },
        "by_risk_level": sorted(
            row["by_risk_level"],
            key=lambda item: RISK_LEVEL_RANK.get(item["risk_level"], 5),
        ),
        "by_pii_type": sorted(
            row["by_pii_type"],
            key=lambda item: (-item["count"], item["pii_type"]),
        ),
        "by_resource_type": sorted(
            row["by_resource_type"],
            key=lambda item: (-item["count"], item["resource_type"]),
        ),
        "by_source": sorted(
            row["by_source"],
            key=lambda item: (-item["count"], item["source"]),
        ),
        "classified_by_day": [
            {"date": item["dt"].strftime("%Y-%m-%d"), "count": item["count"]}
            for item in sorted(row["classified_by_day"], key=lambda item: item["dt"])
        ],
    }

    logger.info(
        f"m=build_payload, msg=executive summary built, as_of={payload['as_of']}"
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
        bucket = config_service.get_config("executive_summary_s3_bucket")
        if bucket is None:
            logger.info(
                f"m={JOB_NAME}, msg=no executive-summary S3 bucket provisioned for "
                "this environment, skipping upload"
            )
        else:
            s3_key = config_service.get_config("executive_summary_s3_key")
            s3_service = S3Service(boto3.resource("s3"))
            destination = f"s3://{bucket}/{s3_key}"
            # In prod, requires the DAG's execution role to have s3:PutObject on
            # this key — tracked as a follow-up to IDPLATF-8284's GetObject-only
            # IAM user, not yet granted. Until it lands, this call fails with
            # AccessDenied in prod (forno already grants emr-forno full access,
            # see quintoandar/infrastructure#45315).
            s3_service.upload_file(payload, destination)
            logger.info(
                f"m={JOB_NAME}, msg=successful S3 put_object, destination={destination}"
            )
