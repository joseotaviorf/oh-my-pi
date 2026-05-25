import argparse
import os
import sys
from os import path

import boto3
import yaml

_COMPILER_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
BI_ETL_EJUICE_ROOT = os.path.dirname(os.path.dirname(_COMPILER_ROOT))
for _p in (BI_ETL_EJUICE_ROOT, _COMPILER_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice.base.paths import BIETLEJUICE_CONFIG_ROOT
from scripts.services.metadata_file_service import (
    MetadataFileService,
)

session = boto3.Session()
client = session.client("s3")
ALL_METADATA_S3_FILE_NAME = "all_lineage_tags_data.yml"


def get_lineage_and_tags_data():
    yamls_data = []
    files = MetadataFileService.list_metadata_files()
    for file, status in files:
        file_info = MetadataFileService.get_info(file)
        yamls_data.append(
            {
                "database_name": file_info.database_name,
                "table_name": file_info.table_name,
                "has_lineage": file_info.has_lineage,
                "has_tags": file_info.has_tags,
            }
        )
    return yamls_data


def upload_one_file(bucket: str, remote_path: str, data):
    """
    Uploads a single file into S3. Used for multiple concurrent requests wchich
    share the same S3 client object.
    Args:
        bucket (str): S3 bucket where files will be uploaded into
        client (boto3.client): S3 client object
        local_path (str): Local dir where the file is placed
        remote_path (str): Remote S3 target object name
    """
    print(f"Uploading file '{remote_path}'")
    client.put_object(
        Body=data, Bucket=bucket, Key=remote_path, ACL="bucket-owner-full-control"
    )
    print(f"Uploaded file 's3://{bucket}/{remote_path}'")


parser = argparse.ArgumentParser()
parser.add_argument(dest="s3_bucket")
args = parser.parse_args()
s3_bucket = args.s3_bucket
global_confs = HierarchicalConf([BIETLEJUICE_CONFIG_ROOT])
dags_packages_files_prefix = global_confs.get_config("dags_packages_files_path_in_s3")
all_lineage_tags_data = get_lineage_and_tags_data()
all_metadata_s3_path = path.join(
    dags_packages_files_prefix, "metadata", ALL_METADATA_S3_FILE_NAME
)
upload_one_file(
    bucket=s3_bucket,
    remote_path=all_metadata_s3_path,
    data=yaml.dump(all_lineage_tags_data),
)
