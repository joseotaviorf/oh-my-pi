import argparse
import logging
import os
import sys
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

boto3.set_stream_logger(__name__, logging.INFO)
logger = logging.getLogger(__name__)

parser = argparse.ArgumentParser(
    description=(
        "Upload bietlejuice/base/sst/pipelines to S3 under "
        "github-repos/bi-etl-ejuice/spark_jobs/sst_pipelines/."
    )
)
parser.add_argument(dest="s3_bucket")
args = parser.parse_args()
s3_bucket = args.s3_bucket

SST_PIPELINES_ROOT = path.join(
    BI_ETL_EJUICE_ROOT,
    "packages",
    "bietlejuice-runtime",
    "src",
    "bietlejuice",
    "base",
    "sst",
    "pipelines",
)
S3_SST_PIPELINES_PREFIX = path.join(
    "github-repos/bi-etl-ejuice", "spark_jobs", "sst_pipelines"
)

if not path.isdir(SST_PIPELINES_ROOT):
    print(f"ERROR: SST pipelines directory not found: {SST_PIPELINES_ROOT}", file=sys.stderr)
    sys.exit(1)

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

for root, _dirs, files in os.walk(SST_PIPELINES_ROOT):
    for file_name in files:
        local_file_path = path.join(root, file_name)
        relative_path = path.relpath(local_file_path, SST_PIPELINES_ROOT)
        s3_object_key = path.join(S3_SST_PIPELINES_PREFIX, relative_path).replace(
            "\\", "/"
        )
        files_to_upload.append((local_file_path, s3_object_key))

with tqdm(
    desc="Uploading sst_pipelines into S3", total=len(files_to_upload)
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
