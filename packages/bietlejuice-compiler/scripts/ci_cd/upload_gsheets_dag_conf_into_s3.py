"""Upload gsheets DAGs' env confs to the Databricks volume, under spark_jobs/{dag}/.

gsheets DAGs keep `forno_conf.yml`/`prod_conf.yml` at the ROOT of the DAG folder (where the
declaration/parse expects them). On the Databricks cluster, however,
`ConfigurationService(dag_name)` reads `sheets_info` from
`{volume}/{prefix}spark_jobs/{dag}/{env}_conf.yml` when the DAG is NOT in the
`bietlejuice_runtime` wheel — the luigijr case, where `get_dag_parent_path` returns None.

forno/prod DAGs resolve this via the wheel (which bundles `dags/`); luigijr DAGs don't, so
this script bridges the gap: it copies each DAG's root `{env}_conf.yml` to `spark_jobs/{dag}/`
on the volume bucket. Scope it with `--include-dir luigijr`.

Unlike `upload_dag_packages_artifact_into_s3.py` (which uploads files under an artifact
folder), here the source is the conf at the DAG ROOT — hence a separate script. Pure Python
(boto3), anchored on an absolute `DAG_PACKAGES_ROOT`, with no cwd/shell dependency.
"""

import argparse
import logging
import os
import sys
from os import path

import boto3
from botocore.config import Config

_COMPILER_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
BI_ETL_EJUICE_ROOT = os.path.dirname(os.path.dirname(_COMPILER_ROOT))
for _p in (BI_ETL_EJUICE_ROOT, _COMPILER_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from dags import DAG_PACKAGES_ROOT

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

S3_SPARK_JOBS_PREFIX = "github-repos/bi-etl-ejuice/spark_jobs"
CONF_FILE_NAMES = ("forno_conf.yml", "prod_conf.yml")

parser = argparse.ArgumentParser()
parser.add_argument(dest="s3_bucket")
parser.add_argument(
    "--include-dir",
    required=False,
    help="Só sobe confs de DAGs sob dags/<DIR>/ (e.g. luigijr).",
)
parser.add_argument(
    "--exclude-dir",
    required=False,
    help="Pula DAGs sob dags/<DIR>/ (e.g. luigijr).",
)
args = parser.parse_args()

client = boto3.Session().client(
    "s3", config=Config(retries={"max_attempts": 5, "mode": "standard"})
)

uploaded = 0
for line_folder in sorted(os.listdir(DAG_PACKAGES_ROOT)):
    line_path = path.join(DAG_PACKAGES_ROOT, line_folder)
    if not path.isdir(line_path):
        continue
    if args.include_dir and line_folder != args.include_dir:
        continue
    if args.exclude_dir and line_folder == args.exclude_dir:
        continue

    for dag_name in sorted(os.listdir(line_path)):
        dag_dir = path.join(line_path, dag_name)
        if not path.isdir(dag_dir):
            continue
        for conf_name in CONF_FILE_NAMES:
            local_path = path.join(dag_dir, conf_name)
            if not path.isfile(local_path):
                continue
            remote_path = f"{S3_SPARK_JOBS_PREFIX}/{dag_name}/{conf_name}"
            logger.info(
                f"Uploading '{local_path}' -> s3://{args.s3_bucket}/{remote_path}"
            )
            client.upload_file(
                local_path,
                args.s3_bucket,
                remote_path,
                ExtraArgs={"ACL": "bucket-owner-full-control"},
            )
            uploaded += 1

logger.info(
    f"Done. Uploaded {uploaded} conf file(s) to s3://{args.s3_bucket}/{S3_SPARK_JOBS_PREFIX}/"
)
