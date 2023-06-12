import argparse
import os
import re

import yaml

from scripts.services.git_service import GitService

from pathlib import Path

from scripts.services.metadata_file_service import MetadataFileService

with open(f"{Path(__file__).parent}/skip_list.yml") as f:
    SKIP_LIST = yaml.safe_load(f)["queries_without_metadata_files"]

SKIP_LIST_PATH_REGEX = re.compile(rf"(?:.*/)?dags/(?P<path>.*)")

metadata_file_service = MetadataFileService()


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
        files = [(input, "A")]
    elif mode == "all_files":
        files = metadata_file_service.list_metadata_files()
    elif mode == "branch":
        git_service = GitService()
        if input == "master":
            from_branch = "HEAD~1"
        else:
            from_branch = "origin/master"
        files = [
            (file, status)
            for file, status in git_service.get_modified_files_from_diff(
                from_branch, "HEAD"
            ).items()
            if status in GitService.UPSERT_STATUS_CODES
        ]
    return list(metadata_file_service.filter_query_files(files))


def remove_prefix(input_string):
    return re.match(SKIP_LIST_PATH_REGEX, input_string).groupdict().get("path")


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
    if results["skipped"]:
        print("Files skipped:")
        for file in results["skipped"]:
            print(file)


def main():
    mode, input, verbose = parse_args()
    query_files = get_query_file_paths(mode, input)
    results = {"passed": [], "failed": [], "skipped": []}

    for file, status in query_files:
        if remove_prefix(file) not in SKIP_LIST:
            if metadata_file_service.sql_file_has_equivalent_metadata_file(
                file, status
            ):
                results["passed"].append(file)
            else:
                results["failed"].append(file)
        else:
            results["skipped"].append(file)

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
