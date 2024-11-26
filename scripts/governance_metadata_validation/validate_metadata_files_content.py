import argparse
import re
from pathlib import Path

import yaml
from yamale import YamaleError

from scripts.services.metadata_file_service import (
    MetadataFileService,
    ReverseMetadataFileException,
    MetricValidateLayerException,
)

from scripts.services.git_service import GitService

with open(f"{Path(__file__).parent}/skip_list.yml") as f:
    SKIP_LIST = yaml.safe_load(f)["metadata_files_out_of_pattern"]

metadata_file_service = MetadataFileService()


SKIP_LIST_PATH_REGEX = re.compile(rf"(?:.*/)?dags/(?P<path>.*)")


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


def get_metadata_file_paths(mode, input):
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
    return list(metadata_file_service.filter_metadata_files(files))


def output_results(results, verbose):
    print(f"Validated {len(results['passed']) + len(results['failed'])} files\n")
    if results["passed"]:
        print(f"Files that passed the validation:")
        for result in results["passed"]:
            print(f"file={result.data}")
        print()
    if results["failed"]:
        print(f"Files that failed the validation:")
        for result in results["failed"]:
            print(f"file={result.data}")
            if verbose:
                for error in result.errors:
                    print(error)
        print()
    if results["skipped"]:
        print("Files skipped:")
        for file in results["skipped"]:
            print(file)


def remove_prefix(input_string):
    return re.match(SKIP_LIST_PATH_REGEX, input_string).groupdict()["path"]


def main():
    mode, input, verbose = parse_args()
    files = get_metadata_file_paths(mode, input)
    results = {"passed": [], "failed": [], "skipped": []}

    for file, status in files:
        if remove_prefix(file) not in SKIP_LIST:
            try:
                result = metadata_file_service.validate_file(file, status)
                results["passed"].append(result[0])
            except YamaleError as error:
                for yaml_err in error.results:
                    if "domain: " in yaml_err.errors:
                        yaml_err.errors = (
                            yaml_err.errors + " Check in DataHub if the domain is valid"
                        )
                    results["failed"].append(yaml_err)
            except ReverseMetadataFileException as error:
                results["failed"].append(error)
            except MetricValidateLayerException as error:
                results["failed"].append(error)
        else:
            results["skipped"].append(file)

    output_results(results, verbose)

    if results["failed"]:
        print("Result: Some validations failed. Make sure all metadata files are valid")
        exit(1)
    else:
        print("Result: All files passed the validations successfully!")


if __name__ == "__main__":
    main()
