import argparse
import glob
import json
import os
import sys
from typing import Dict, List, Optional

import boto3
import requests
import yaml

_COMPILER_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
_REPO_ROOT = os.path.dirname(os.path.dirname(_COMPILER_ROOT))
for _p in (_REPO_ROOT, _COMPILER_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from bietlejuice.base.pipeline.platform_resolver import resolve_platforms
from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from bietlejuice.governance.domain_registry import catalog_mapping_for
from scripts.services.git_service import GitService
from scripts.services.metadata_file_info import MetadataFileInfo
from scripts.services.metadata_file_service import (
    _DAG_DIR_FROM_METADATA_PATH,
    MetadataFileService,
)


def parse_args():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
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

    commit = group.add_argument_group()
    commit.add_argument(
        "--from-commit", help="if uses commit as checkpoint. Get the start commit"
    )

    commit.add_argument(
        "--to-commit", help="if uses commit as checkpoint. Get the ends commit"
    )

    parser.add_argument("--bucket", help="S3 Bucket where data should be stored")
    parser.add_argument("--host", help="Metadata Propagator hostname to be used")
    args = parser.parse_args()
    all_files = args.all
    bucket = args.bucket
    host = args.host
    branch = args.branch
    from_commit = args.from_commit
    to_commit = args.to_commit
    file = args.file
    return bucket, host, all_files, branch, from_commit, to_commit, file


def filter_new_and_changed_files(files_and_status, upsert_status_codes):
    return [
        (file, status)
        for file, status in files_and_status.items()
        if status in upsert_status_codes
    ]


def get_metadata_files(all_files, branch, from_commit, to_commit, file):
    metadata_file_service = MetadataFileService()
    if all_files:
        return list(metadata_file_service.list_metadata_files())
    elif file:
        return [(file, "M")]
    elif branch:
        git_service = GitService()
        from_branch = resolve_diff_from_ref(branch)

        changed_files = [
            (file, status)
            for file, status in git_service.get_modified_files_from_diff(
                from_branch, "HEAD"
            ).items()
            if status in git_service.UPSERT_STATUS_CODES
        ]
        metadata_files = metadata_file_service.filter_metadata_files(changed_files)
        return metadata_files

    elif from_commit and to_commit:
        git_service = GitService()
        changed_files = filter_new_and_changed_files(
            git_service.get_modified_files_from_diff(from_commit, to_commit),
            git_service.UPSERT_STATUS_CODES,
        )

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
    base_path = "/woodpecker/src/github.com/quintoandar/bi-etl-ejuice"
    sql_file_path = (
        metric_path.replace("metadata", "queries")
        .replace(".yaml", ".sql")
        .replace(".yml", ".sql")
    )
    safe_path = os.path.realpath(sql_file_path)
    common_base = os.path.commonpath([base_path, safe_path])
    if common_base != base_path:
        print(
            f"common_base = {common_base}, base_path = {base_path}, safe_path = {safe_path}"
        )
        raise ValueError("Invalid commom path")
    with open(sql_file_path) as sql_file:
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

    with open(file_info.local_path) as metric_file:
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
                    **{
                        key: value
                        for key, value in metric.items()
                        if key in optional_args
                    },
                }
            )

    return payload


def resolve_platforms_for_file(file_info: MetadataFileInfo) -> Optional[List[str]]:
    """Resolve the DataHub platforms a table should be propagated to.

    Reads the table's DAG declaration (``*_declaration.yml`` in the DAG dir,
    derived from the metadata file path) and delegates to
    ``bietlejuice.base.pipeline.platform_resolver``. Returns ``None`` on any
    problem (missing declaration/type, resolution error) so the propagator
    falls back to its legacy single-target behavior.
    """
    try:
        # Derive the DAG dir via the canonical regex, which tolerates an optional
        # subdir under the layer (``metadata/<layer>[/<subdir>]/<table>.yml``).
        # Counting dirname() levels breaks on that nested form (lands on ``metadata/``).
        dag_dir_match = _DAG_DIR_FROM_METADATA_PATH.match(file_info.local_path)
        if not dag_dir_match:
            return None
        dag_dir = dag_dir_match.group(1)
        matches = glob.glob(os.path.join(dag_dir, "*_declaration.yml"))
        if not matches:
            return None
        with open(matches[0]) as declaration_file:
            declaration = yaml.safe_load(declaration_file) or {}
        workflow = declaration.get("workflow") or {}
        workflow_type = workflow.get("type")
        if not workflow_type:
            return None
        table_customization = (workflow.get("tables_customization") or {}).get(
            file_info.table_name, {}
        ) or {}
        return resolve_platforms(workflow_type, workflow, table_customization)
    except Exception as error:  # never break the CI upload over one declaration
        print(
            f"m=resolve_platforms_for_file, table={file_info.table_name}, "
            f"msg=Falling back to default platform, error={error}"
        )
        return None


def resolve_datahub_domain_urn_for_file(
    file_info: MetadataFileInfo,
) -> Optional[str]:
    """Resolve the DataHub domain URN leaf from metadata ``domain:`` + catalog_mappings.

    Reads the table's metadata YAML and looks up ``catalog_mappings`` in
    ``domains.yml``. Returns ``None`` when the domain is unmapped or unreadable so
    the propagator keeps its legacy display-name normalization.
    """
    try:
        with open(file_info.local_path, encoding="utf-8") as metadata_file:
            metadata = yaml.safe_load(metadata_file) or {}
        metadata_domain = metadata.get("domain")
        if not metadata_domain:
            return None
        row = catalog_mapping_for(str(metadata_domain).strip())
        if row is None:
            return None
        return row.get("datahub_urn_leaf")
    except Exception as error:
        print(
            f"m=resolve_datahub_domain_urn_for_file, table={file_info.table_name}, "
            f"msg=Falling back to legacy domain slug, error={error}"
        )
        return None


def generate_documentation_payload(file_info: MetadataFileInfo) -> Dict:
    payload = {
        "vendor": ["datahub"],
        "database_name": file_info.database_name,
        "table_name": file_info.table_name,
    }
    platforms = resolve_platforms_for_file(file_info)
    if platforms:
        payload["platforms"] = platforms
    datahub_domain_urn = resolve_datahub_domain_urn_for_file(file_info)
    if datahub_domain_urn:
        payload["datahub_domain_urn"] = datahub_domain_urn
    return payload


def generate_payloads(files_info: List[MetadataFileInfo]):
    doc_payloads = {"documentation": [], "metricEntity": []}

    for file_info in files_info:
        if file_info.has_documentation:
            doc_payloads["documentation"].append(
                generate_documentation_payload(file_info)
            )
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
    bucket, host, all_files, branch, from_commit, to_commit, file = parse_args()
    files = get_metadata_files(all_files, branch, from_commit, to_commit, file)

    if not files:
        print("m=main, msg=No files found to upload.")
        exit(0)

    files_info = []
    for file, _ in files:
        try:
            files_info.append(MetadataFileService.get_info(file))
        except FileNotFoundError:
            print(f"The file {file} not exists. Maybe the file was deleted.")

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
