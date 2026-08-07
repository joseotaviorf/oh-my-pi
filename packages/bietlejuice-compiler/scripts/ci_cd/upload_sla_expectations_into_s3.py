"""Publish SLA YAML expectations to the data-documentation bucket on S3.

Runs at CI/deploy time (not per Airflow run). The EMR ``sweep_empty_partitions``
job reads ``sla/sla_expectations.json`` from ``data_documentation_bucket``.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys

import boto3
from botocore.config import Config

from bietlejuice.observability.monitoring.constants import SLA_EXPECTATIONS_S3_KEY
from bietlejuice.observability.monitoring.sla_expectations import (
    dump_expectations_json,
    load_sla_expectations,
)

_COMPILER_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
_REPO_ROOT = os.path.dirname(os.path.dirname(_COMPILER_ROOT))
for _path in (_REPO_ROOT, _COMPILER_ROOT):
    if _path not in sys.path:
        sys.path.insert(0, _path)

from dags import DAG_PACKAGES_ROOT

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _bucket_name(raw: str) -> str:
    return raw.removeprefix("s3://").strip("/").split("/", 1)[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "bucket",
        help="Data-documentation bucket (e.g. data-documentation.s3.forno.data.quintoandar.com.br)",
    )
    args = parser.parse_args()
    bucket = _bucket_name(args.bucket)

    if not DAG_PACKAGES_ROOT:
        raise RuntimeError("DAG_PACKAGES_ROOT is not set; cannot load SLA YAML files.")

    expectations = load_sla_expectations(DAG_PACKAGES_ROOT)
    payload = dump_expectations_json(expectations)

    client = boto3.Session().client(
        "s3", config=Config(retries={"max_attempts": 5, "mode": "standard"})
    )
    client.put_object(
        Bucket=bucket,
        Key=SLA_EXPECTATIONS_S3_KEY,
        Body=payload.encode("utf-8"),
        ContentType="application/json",
        ACL="bucket-owner-full-control",
    )
    logger.info(
        "Published %s SLA expectation(s) to s3://%s/%s",
        len(expectations),
        bucket,
        SLA_EXPECTATIONS_S3_KEY,
    )


if __name__ == "__main__":
    main()
