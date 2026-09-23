import argparse
import re
from pathlib import Path

import yaml
from yamale import YamaleError

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from scripts.ci_cd.domain_cli import (
    branch_name_arg_type,
    domain_arg_type,
    repo_relative_file_arg_type,
)
from scripts.services.git_service import GitService
from scripts.services.metadata_file_service import (
    DatabaseNameMismatchException,
    MetadataFileService,
    MetricValidateLayerException,
    TableNameMismatchException,
)

with open(f"{Path(__file__).parent}/skip_list.yml") as f:
    SKIP_LIST = yaml.safe_load(f)["metadata_files_out_of_pattern"]

metadata_file_service = MetadataFileService()


SKIP_LIST_PATH_REGEX = re.compile(r"(?:.*/)?dags/(?P<path>.*)")


def _sanitized_domain(value):
    if value is None:
        return None
    return domain_arg_type(value)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-v",
        "--verbose",
        help="Output more detailed messages",
        action="store_true",
        required=False,
    )
    parser.add_argument(
        "--domain",
        type=domain_arg_type,
        help="Restrict validation to a specific domain folder under dags/ (e.g. for_rent, fintech)",
        required=False,
        default=None,
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "-f",
        "--file",
        type=repo_relative_file_arg_type,
        help="Path to a metadata file to be validated",
        required=False,
    )
    group.add_argument(
        "-b",
        "--branch",
        type=branch_name_arg_type,
        help="Branch to be validated",
        required=False,
    )
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
    if branch is not None:  # detect via presence, not truthiness (value may be "")
        mode = "branch"
    if all_files:
        mode = "all_files"
    return mode, (file or branch or all_files), verbose, _sanitized_domain(args.domain)


def get_metadata_file_paths(mode, input, domain=None):
    files = []
    if domain is not None:
        domain = domain_arg_type(domain)
    if mode == "file":
        input = repo_relative_file_arg_type(input)
        files = [(input, "A")]
    elif mode == "all_files":
        files = metadata_file_service.list_metadata_files()
    elif mode == "branch":
        git_service = GitService()
        if not input:
            import subprocess

            input = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
            ).strip()
        input = branch_name_arg_type(input)
        from_branch = resolve_diff_from_ref(input)
        files = [
            (file, status)
            for file, status in git_service.get_modified_files_from_diff(
                from_branch, "HEAD"
            ).items()
            if status in GitService.UPSERT_STATUS_CODES
        ]
    result = list(metadata_file_service.filter_metadata_files(files))
    result = [(f, s) for f, s in result if not f.startswith("dags/platform/migration_")]
    if domain:
        domain_prefix = f"dags/{domain}/"
        result = [(f, s) for f, s in result if f.startswith(domain_prefix)]
    return result


def _format_validation_error(error):
    """Return (file_path or None, list of human-readable error lines)."""
    file_path = getattr(error, "data", None)
    if getattr(error, "errors", None):
        return file_path, list(error.errors)
    return file_path, [str(error).strip()]


def _print_validation_failures(failures, indent=""):
    for error in failures:
        file_path, messages = _format_validation_error(error)
        if file_path:
            print(f"{indent}{file_path}")
            message_indent = indent + "  "
        else:
            message_indent = indent
        for message in messages:
            print(f"{message_indent}{message}")


def output_results(results, verbose):
    print(f"Validated {len(results['passed']) + len(results['failed'])} files\n")
    if results["passed"]:
        print("Files that passed the validation:")
        for result in results["passed"]:
            print(f"{result}")
        print()
    if results["failed"]:
        print("Files that failed the validation:")
        _print_validation_failures(results["failed"], indent="  ")
        print()
    if results["skipped"]:
        print("Files skipped:")
        for file in results["skipped"]:
            print(file)


def remove_prefix(input_string):
    return re.match(SKIP_LIST_PATH_REGEX, input_string).groupdict()["path"]


def main():
    mode, input, verbose, domain = parse_args()
    files = get_metadata_file_paths(mode, input, domain=domain)
    results = {"passed": [], "failed": [], "skipped": []}

    for file, status in files:
        if remove_prefix(file) not in SKIP_LIST:
            try:
                result = metadata_file_service.validate_file(file, status)
                results["passed"].append(result[0])
            except YamaleError as error:
                results["failed"].append(error)
            except MetricValidateLayerException as error:
                results["failed"].append(error)
            except TableNameMismatchException as error:
                results["failed"].append(error)
            except DatabaseNameMismatchException as error:
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
