import argparse
import glob
from os import path
import yaml
import os
import sys
import boto3
from itertools import chain

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from bietlejuice.base.paths import DATALAKE_METADATA_PATH
from hierarchical_conf.hierarchical_conf import HierarchicalConf

from dags import DAG_PACKAGES_ROOT

session = boto3.Session()
client = session.client("s3")
ALL_METADATA_S3_FILE_NAME = "all_lineage_tags_data.yml"


def list_metadata_files_from_dag_packages_in_composer():
    """
    Yields all metadata YAML file paths from dag packages.

    * Method used only in Composer *

    :return: A generator that yields metadata file paths
    """
    for extension in ("*.yml", "*.yaml"):
        for file in glob.iglob(
            f"{DAG_PACKAGES_ROOT}/**/metadata/**/{extension}", recursive=True
        ):
            yield file


def list_metadata_files_from_legacy_structure():
    """
    Yields all metadata YAML file paths from legacy structure (bietlejuice).

    :return: A generator that yields metadata file paths
    """
    for extension in ("*.yml", "*.yaml"):
        for file in glob.iglob(
            f"{DATALAKE_METADATA_PATH}/**/{extension}", recursive=True
        ):
            yield file


def get_first_key(input_dict: dict) -> str:
    """
    returns the first key of a dict
    it is expected that the key is a string
    """
    return next(iter(input_dict))


def get_lineage_and_tags_data():
    yamls_data = []
    dag_packages_metadata_files = list_metadata_files_from_dag_packages_in_composer()
    legacy_structure_metadata_files = list_metadata_files_from_legacy_structure()
    all_metadata_files = chain(
        dag_packages_metadata_files, legacy_structure_metadata_files
    )
    for file in all_metadata_files:
        with open(file, "r") as fp:
            data = yaml.safe_load(fp)
            db_name = data["database_name"]
            tb_name = data["table_name"]
            columns = data.get("columns")
            if not columns:
                file_type = "tags"
            else:
                first_column_key = get_first_key(columns)
                file_type = get_first_key(data["columns"][first_column_key])

        yamls_data.append(
            {
                "database_name": db_name,
                "table_name": tb_name,
                "has_lineage": file_type == "lineage",
                "has_tags": file_type == "tags",
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
    client.put_object(Body=data, Bucket=bucket, Key=remote_path, ACL="bucket-owner-full-control")
    print(f"Uploaded file 's3://{bucket}/{remote_path}'")

parser = argparse.ArgumentParser()
parser.add_argument(dest="s3_bucket")
args = parser.parse_args()
s3_bucket = args.s3_bucket
global_confs = HierarchicalConf([BIETLEJUICE_PROJECT_ROOT])
dags_packages_files_prefix = global_confs.get_config(
    "dags_packages_files_path_in_s3"
)
all_lineage_tags_data = get_lineage_and_tags_data()
all_metadata_s3_path = path.join(
    dags_packages_files_prefix, "metadata", ALL_METADATA_S3_FILE_NAME
)
upload_one_file(
    bucket=s3_bucket,
    remote_path=all_metadata_s3_path,
    data=yaml.dump(all_lineage_tags_data),
)
