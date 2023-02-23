import argparse
import os
import re

import yaml

from bietlejuice.services import FileService
from scripts.services.git_service import GitService
from dags import DAG_PACKAGES_ROOT

from pathlib import Path

SQL_PATH_REGEX = re.compile(
    rf"(?:.*/)?dags/(?P<domain>\w+)/(?P<context>\w+)/queries/(?P<layer>\w+)(?:/\w+)?/(?P<table_name>\w+)\.sql"
)
DAG_FILES_PREFIX = f"{DAG_PACKAGES_ROOT}/"

with open(f"{Path(__file__).parent}/skip_list.yml") as f:
    SKIP_LIST = yaml.safe_load(f)["queries_without_metadata_files"]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-v",
        "--verbose",
        help="Output more detailed messages",
        action="store_true",
        required=False,
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "-f", "--file", help="Path to a metadata file to be validated", required=False
    )
    group.add_argument("-b", "--branch", help="Branch to be validated", required=False)
    group.add_argument(
        "-a",
        "--all-files",
        help="Validate all metadata files",
        action="store_true",
        required=False,
    )
    args = parser.parse_args()
    file = args.file
    branch = args.branch
    all_files = args.all_files
    verbose = args.verbose
    mode = None
    if file:
        mode = "file"
    if branch:
        mode = "branch"
    if all_files:
        mode = "all_files"
    return mode, (file or branch or all_files), verbose


def get_query_file_paths(mode, input):
    files = []
    if mode == "file":
        files = [input]
    elif mode == "all_files":
        files = list(FileService.list_all_files_recursively(DAG_PACKAGES_ROOT, "sql"))
    elif mode == "branch":
        git_service = GitService()
        if input == "master":
            from_branch = "HEAD~1"
        else:
            from_branch = "origin/master"
        files = [
            file
            for file, status in git_service.get_modified_files_from_diff(
                from_branch, "HEAD"
            ).items()
            if status in git_service.UPSERT_STATUS_CODES
            and re.match(SQL_PATH_REGEX, file)
        ]
    return files


def metadata_file_exists(query_file):
    return os.path.isfile(
        query_file.replace("/queries/", "/metadata/").replace("sql", "yml")
    ) or os.path.isfile(
        query_file.replace("/queries/", "/metadata/").replace("sql", "yaml")
    )


def remove_prefix(input_string, prefix=DAG_FILES_PREFIX):
    if prefix and input_string.startswith(prefix):
        return input_string[len(prefix) :]
    return input_string


def output_results(results):
    print(f"Validated {len(results['passed']) + len(results['failed'])} files\n")
    if results["passed"]:
        print(f"Queries that have a corresponding metadata file:")
        for result in results["passed"]:
            print(f"file={result}")
        print()
    if results["failed"]:
        print(f"Queries that don't have a corresponding metadata file:")
        for result in results["failed"]:
            print(f"file={result}")
        print()


def main():
    mode, input, verbose = parse_args()
    query_files = get_query_file_paths(mode, input)
    results = {"passed": [], "failed": []}

    for file in query_files:
        if remove_prefix(file) not in SKIP_LIST:
            if metadata_file_exists(file):
                results["passed"].append(file)
            else:
                results["failed"].append(file)

    output_results(results)

    if results["failed"]:
        print(
            "Result: Some queries do not have corresponding metadata files. Make sure all SQL files have a corresponding metadata file"
        )
        exit(1)
    else:
        print("Result: All query files have a corresponding metadata file")


if __name__ == "__main__":
    main()
