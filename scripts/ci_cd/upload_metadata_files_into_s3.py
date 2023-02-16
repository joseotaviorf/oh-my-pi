import argparse
from typing import List

import boto3
import requests

from bietlejuice.services.git_service import GitService
from bietlejuice.services.metadata_services.metadata_file_info import MetadataFileInfo
from bietlejuice.services.metadata_services.metadata_file_service import (
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
    parser.add_argument("--bucket", help="S3 Bucket where data should be stored")
    parser.add_argument("--host", help="Metadata Propagator hostname to be used")
    args = parser.parse_args()
    all_files = args.all
    bucket = args.bucket
    host = args.host
    branch = args.branch
    return bucket, host, all_files, branch


def get_metadata_files(all_files, branch):
    metadata_file_service = MetadataFileService()
    if all_files:
        return list(metadata_file_service.list_metadata_files())
    elif branch:
        git_service = GitService()
        if branch == "master":
            from_branch = "HEAD~1"
        else:
            from_branch = "origin/master"
        changed_files = [
            f"{file}"
            for file, status in git_service.get_modified_files_from_diff(
                from_branch, "HEAD"
            ).items()
            if status in git_service.UPSERT_STATUS_CODES
        ]
        metadata_files = list(
            metadata_file_service.filter_metadata_files(changed_files)
        )
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


def generate_payloads(files_info: List[MetadataFileInfo]):
    doc_payloads = []
    for file_info in files_info:
        if file_info.has_documentation:
            doc_payloads.append(
                {
                    "vendor": ["datahub"],
                    "database_name": file_info.database_name,
                    "table_name": file_info.table_name,
                }
            )
    return doc_payloads


def call_mp(payloads, host, endpoint, items_per_call=100):
    for idx in range(0, len(payloads), items_per_call):
        requests.post(f"{host}/{endpoint}", json=payloads[idx : idx + items_per_call])


def send_metadata_to_mp(files_info, host):
    doc_payloads = generate_payloads(files_info)
    call_mp(doc_payloads, host, "documentation")


def get_files_info(files):
    files_info = []
    for file in files:
        files_info.append(MetadataFileService.get_info(file))
    return files_info


def main():
    bucket, host, all_files, branch = parse_args()
    files = get_metadata_files(all_files, branch)
    files_info = [MetadataFileService.get_info(file) for file in files]

    print("m=main, msg=Files to be uploaded:")
    for file_info in files:
        print(f"file_path={file_info.local_path}")

    print("m=main, msg=Uploading files to s3...")
    upload_files(files_info, bucket)
    print("m=main, msg=Uploaded files to s3")

    print("m=main, msg=Sending changes to Metadata Propagator")
    send_metadata_to_mp(files_info, host)
    print("m=main, msg=Changes sent to Metadata Propagator")


if __name__ == "__main__":
    main()
