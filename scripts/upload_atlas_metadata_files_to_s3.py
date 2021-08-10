import argparse
import glob
import os

from yaml import safe_load
import boto3

ABS_PATH = os.path.dirname(os.path.realpath(__file__))


def get_first_key(input_dict: dict) -> str:
    """
    returns the first key of a dict
    it is expected that the key is a string
    """
    return next(iter(input_dict))


def get_remote_path_from_yml_file(yml_path: str) -> str:
    """
    given a path to a yml file containing Atlas metadata info,
    reads the file and generates a path where it should be stored in S3

    Args:
        yml_path: path where the metadata file is stored locally
        e.g:
            /../bi-etl-ejuice/jobs/composer/db/datalake/metadata/monopoly/clean/person_sale.yml
            /../bi-etl-ejuice/jobs/composer/db/datalake/metadata/metabase/raw/metabase_table.yml

    Returns:
        a string representing the path where this file should be stored in S3
        e.g:
            lineage/atlas/datalake_monopoly_clean/person_sale.yml
            tags/atlas/datalake_metabase_raw/metabase_table.yml
    """
    with open(yml_path, "r") as fp:
        data = safe_load(fp)
        db_name = data["database_name"]
        table_name = data["table_name"]
        first_column_key = get_first_key(data["columns"])
        file_type = get_first_key(data["columns"][first_column_key])
        if file_type not in ["lineage", "tags"]:
            raise ValueError(f"File {yml_path} has invalid type: {file_type}")

    return f"{file_type}/atlas/{db_name}/{table_name}.yml"


def main():
    """
    This script reads Atlas metadata files and uploads them to the data-documentation S3 bucket.
    It is expected that each file is stored in the following format:

    bietlejuice/jobs/composer/db/datalake/metadata/{source}/{layer}/{table-name}.yml

    And each file should have lineage OR tags definitions for the table columns
    """
    parser = argparse.ArgumentParser()
    parser.add_argument(dest="metadata_s3_bucket")
    args = parser.parse_args()

    metadata_s3_bucket = args.metadata_s3_bucket
    s3 = boto3.client("s3")

    for extension in ("*.yml", "*.yaml"):
        files = glob.glob(
            f"{ABS_PATH}/../bietlejuice/jobs/composer/db/datalake/metadata/**/{extension}",
            recursive=True,
        )
        if files:
            for file_path in files:
                remote_path = get_remote_path_from_yml_file(file_path)
                s3.upload_file(
                    file_path,
                    metadata_s3_bucket,
                    remote_path,
                    ExtraArgs={"ACL": "bucket-owner-full-control"},
                )
                print(
                    f"local_path={file_path}, remote_path={remote_path}, msg=Metadata file saved to S3"
                )
        else:
            print(
                f"msg=No files found!"
            )


if __name__ == "__main__":
    main()
