import argparse
import logging
import os
import re
import sys
import tempfile
import zipfile
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial
from os import path

import boto3
from botocore.config import Config
from tqdm import tqdm

_COMPILER_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
BI_ETL_EJUICE_ROOT = os.path.dirname(os.path.dirname(_COMPILER_ROOT))
for _p in (BI_ETL_EJUICE_ROOT, _COMPILER_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from dags import DAG_PACKAGES_ROOT

boto3.set_stream_logger(__name__, logging.INFO)
logger = logging.getLogger(__name__)

parser = argparse.ArgumentParser()
parser.add_argument(dest="s3_bucket")
parser.add_argument(dest="artifact")
parser.add_argument(
    "--include-dir",
    required=False,
    help="Only upload artifacts whose path is under dags/<DIR>/ (e.g. luigijr). Used by "
    "the luigijr esteira to sync ONLY its DAGs to the forno Databricks volume.",
)
parser.add_argument(
    "--exclude-dir",
    required=False,
    help="Skip artifacts whose path is under dags/<DIR>/ (e.g. luigijr). Mirrors the "
    "create_dag_files build barrier so the forno/prod volume never gets luigijr files.",
)
args = parser.parse_args()
s3_bucket = args.s3_bucket
artifact = args.artifact
include_dir = args.include_dir
exclude_dir = args.exclude_dir

S3_DAGS_PACKAGES_PATH_PREFIX = path.join("github-repos/bi-etl-ejuice/", artifact)

config = Config(retries={"max_attempts": 5, "mode": "standard"})
session = boto3.Session()
client = session.client("s3", config=config)


def upload_one_file(
    bucket: str, client: boto3.client, local_path: str, remote_path: str
):
    """
    Uploads a single file into S3. Used for multiple concurrent requests wchich
    share the same S3 client object.
    Args:
        bucket (str): S3 bucket where files will be uploaded into
        client (boto3.client): S3 client object
        local_path (str): Local dir where the file is placed
        remote_path (str): Remote S3 target object name
    """
    logger.info(f"Uploading file '{local_path}'")
    client.upload_file(
        local_path, bucket, remote_path, ExtraArgs={"ACL": "bucket-owner-full-control"}
    )
    logger.info(f"Uploaded file 's3://{bucket}/{remote_path}'")


func = partial(upload_one_file, s3_bucket, client)

files_to_upload = []
# dag_name -> list of local file paths under its spark_jobs/ tree, only tracked
# for DAGs whose spark_jobs package has subdirectories (nested absolute
# imports like `dags.agents.<dag>.spark_jobs.framework.x` can't resolve from
# flat --py-files, so those DAGs also get a structure-preserving pkg.zip).
nested_spark_job_files = defaultdict(list)

for root, dirs, files in os.walk(DAG_PACKAGES_ROOT):
    if f"/{artifact}" not in root:
        continue
    if include_dir and f"/{include_dir}/" not in f"{root}/":
        continue
    if exclude_dir and f"/{exclude_dir}/" in f"{root}/":
        continue

    for file_name in files:
        dag_path, artifact_path = re.split(f"/{artifact}", root)
        dag_path = f"{dag_path}/"
        dag_name = "/".join(
            list(filter(None, dag_path.replace(DAG_PACKAGES_ROOT, "").split("/")))[1:]
        )

        spark_job_local_path = path.join(root, file_name)
        spark_job_s3_path = path.join(
            S3_DAGS_PACKAGES_PATH_PREFIX, dag_name, artifact_path.strip("/"), file_name
        )
        files_to_upload.append((spark_job_local_path, spark_job_s3_path))

        if artifact == "spark_jobs" and artifact_path.strip("/"):
            nested_spark_job_files[dag_name].append(spark_job_local_path)

REPO_ROOT = path.dirname(DAG_PACKAGES_ROOT)
_tmp_zip_dir = tempfile.mkdtemp(prefix="spark_jobs_pkg_")
for dag_name, local_files in nested_spark_job_files.items():
    zip_local_path = path.join(_tmp_zip_dir, f"{dag_name.replace('/', '_')}_pkg.zip")
    with zipfile.ZipFile(zip_local_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(path.join(DAG_PACKAGES_ROOT, "__init__.py"), "dags/__init__.py")
        for local_file in local_files:
            zf.write(local_file, path.relpath(local_file, REPO_ROOT))
    zip_s3_path = path.join(S3_DAGS_PACKAGES_PATH_PREFIX, dag_name, "pkg.zip")
    files_to_upload.append((zip_local_path, zip_s3_path))

with tqdm(
    desc=f"Uploading {artifact} into S3", total=len(files_to_upload)
) as progress_bar:
    with ThreadPoolExecutor(max_workers=64) as executor:
        futures = {
            executor.submit(func, *file_to_upload): file_to_upload
            for file_to_upload in files_to_upload
        }
        for future in as_completed(futures):
            if future.exception():
                raise future.exception()
            progress_bar.update(1)
