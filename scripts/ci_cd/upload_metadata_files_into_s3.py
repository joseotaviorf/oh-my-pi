import os
import argparse
from typing import List, Dict

import boto3
import requests
import json
import yaml

from scripts.services.git_service import GitService
from scripts.services.metadata_file_info import MetadataFileInfo
from scripts.services.metadata_file_service import (
    MetadataFileService,
)


def parse_args():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--all",
        help="If all metadata files should be uploaded",
        action="store_true",
        required=False,
    )
    group.add_argument(
        "--branch",
        help="Compare changes from current branch to a specific branch",
        required=False,
    )
    group.add_argument(
        "--file",
        help="If only a specific metadata yml file should be uploaded",
        required=False,
    )
    parser.add_argument("--bucket", help="S3 Bucket where data should be stored")
    parser.add_argument("--host", help="Metadata Propagator hostname to be used")
    args = parser.parse_args()
    all_files = args.all
    bucket = args.bucket
    host = args.host
    branch = args.branch
    file = args.file
    return bucket, host, all_files, branch, file


def get_metadata_files(all_files, branch, file):
    metadata_file_service = MetadataFileService()
    if all_files:
        return list(metadata_file_service.list_metadata_files())
    elif file:
        return [(file, "M")]
    elif branch:
        git_service = GitService()
        if branch == "master":
            from_branch = "HEAD~1"
        else:
            from_branch = "origin/master"
            git_service.fetch("master") # We need to do this because Woodpecker will only fetch from the current branch.
        
        changed_files = [
            (file, status)
            for file, status in git_service.get_modified_files_from_diff(
                from_branch, "HEAD"
            ).items()
            if status in git_service.UPSERT_STATUS_CODES
        ]
        metadata_files = metadata_file_service.filter_metadata_files(changed_files)
        return metadata_files


def upload_files(files: List[MetadataFileInfo], bucket):
    s3 = boto3.client("s3")
    for file in files:
        # TODO: remove specific folders upload once we migrate to new file structure
        if file.has_tags:
            s3.upload_file(
                file.local_path,
                bucket,
                file.s3_path.replace("metadata/", "tags/atlas/"),
                ExtraArgs={"ACL": "bucket-owner-full-control"},
            )
        if file.has_lineage:
            s3.upload_file(
                file.local_path,
                bucket,
                file.s3_path.replace("metadata/", "lineage/atlas/"),
                ExtraArgs={"ACL": "bucket-owner-full-control"},
            )
        if file.has_documentation:
            s3.upload_file(
                file.local_path,
                bucket,
                file.s3_path.replace("metadata/", "documentation/"),
                ExtraArgs={"ACL": "bucket-owner-full-control"},
            )
        s3.upload_file(
            file.local_path,
            bucket,
            file.s3_path,
            ExtraArgs={"ACL": "bucket-owner-full-control"},
        )


def metric_qualculation_method(metric_path: str) -> str:
    base_path = "/bi-etl-ejuice"
    sql_file_path = metric_path.replace("metadata", "queries").replace(".ymal", ".sql").replace(".yml", ".sql")
    safe_path = os.path.realpath(sql_file_path)
    common_base = os.path.commonpath([base_path, safe_path]) 
    if common_base != base_path:
        print(f"common_base = {common_base}, base_path = {base_path}, safe_path = {safe_path}")
        raise ValueError("Invalid commom path")
    with open(sql_file_path, "r") as sql_file:
        return json.dumps(sql_file.read())


def generate_metric_payload(file_info: MetadataFileInfo) -> List[Dict]:

    optional_args = [
        "acronym",
        "business_stage",
        "company_line",
        "is_additive",
        "hierarchy_level",
        "link_to_metric",
        "approved_by",
        "observations",
    ]

    with open(file_info.local_path, "r") as metric_file:
        metric_data = yaml.safe_load(metric_file)

    payload = []
    for column, doc in metric_data["columns"].items():
        metric = doc.get("metric")
        if metric:
            payload.append(
                {
                    "vendor": ["datahub"],
                    "metric_source": "METRIC LAYER",
                    "name": metric["name"],
                    "description": metric["description"],
                    "company_line": metric_data["domain"],
                    "created_by": metric_data["owner"],
                    "maturity_level": "Official",
                    "calculation": metric_qualculation_method(file_info.local_path),
                    **{key: value for key, value in metric.items() if key in optional_args}
                }
            )

    return payload


def generate_documentation_payload(file_info: MetadataFileInfo) -> Dict:
    return {
        "vendor": ["datahub"],
        "database_name": file_info.database_name,
        "table_name": file_info.table_name,
    }


def generate_payloads(files_info: List[MetadataFileInfo]):
    doc_payloads = {
        "documentation": [],
        "metricEntity": []
    }

    for file_info in files_info:
        if file_info.has_documentation:
            doc_payloads["documentation"].append(generate_documentation_payload(file_info))
        if file_info.has_metric:
            doc_payloads["metricEntity"] += generate_metric_payload(file_info)

    return doc_payloads


def call_mp(payloads, host, endpoint, items_per_call=100):
    for idx in range(0, len(payloads), items_per_call):
        requests.post(f"{host}/{endpoint}", json=payloads[idx : idx + items_per_call])


def send_metadata_to_mp(files_info, host):
    payloads = generate_payloads(files_info)
    for path, payload in payloads.items():
        call_mp(payload, host, path)


def main():
    bucket, host, all_files, branch, file = parse_args()
    files = get_metadata_files(all_files, branch, file)

    if not files:
        print("m=main, msg=No files found to upload.")
        exit(0)

    files_info = [MetadataFileService.get_info(file) for file, status in files]

    print("m=main, msg=Files to be uploaded:")
    for file_info in files_info:
        print(f"file_path={file_info.local_path}")

    print("m=main, msg=Uploading files to s3...")
    upload_files(files_info, bucket)
    print("m=main, msg=Uploaded files to s3")

    print("m=main, msg=Sending changes to Metadata Propagator")
    send_metadata_to_mp(files_info, host)
    print("m=main, msg=Changes sent to Metadata Propagator")


if __name__ == "__main__":
    main()
