import argparse
import logging
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial
from os import path

import boto3
from botocore.config import Config
from tqdm import tqdm

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from dags import DAG_PACKAGES_ROOT

boto3.set_stream_logger(__name__, logging.INFO)
logger = logging.getLogger(__name__)

parser = argparse.ArgumentParser()
parser.add_argument(dest="s3_bucket")
parser.add_argument(dest="artifact")
args = parser.parse_args()
s3_bucket = args.s3_bucket
artifact = args.artifact

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

for root, dirs, files in os.walk(DAG_PACKAGES_ROOT):
    if f"/{artifact}" not in root:
        continue

    for file_name in files:
        dag_path, artifact_path = re.split(f"/{artifact}", root)
        dag_path = f"{dag_path}/"
        dag_name = "/".join(
            list(filter(None, dag_path.replace(DAG_PACKAGES_ROOT, "").split("/")))[1:]
        )

        spark_job_local_path = path.join(root, file_name)
        spark_job_s3_path = path.join(S3_DAGS_PACKAGES_PATH_PREFIX, dag_name, artifact_path.strip("/"), file_name)
        files_to_upload.append((spark_job_local_path, spark_job_s3_path))

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
