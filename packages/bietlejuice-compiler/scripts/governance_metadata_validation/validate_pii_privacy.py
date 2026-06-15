"""Validate columns.*.privacy sections against the PII catalog and RAE controls.

CI orchestration entrypoint; validation rules live in ``pii_privacy_checks.py``.

CLI output uses print() like sibling metadata validators (validate_metadata_files_content,
validate_metadata_files_exist) so Woodpecker captures human-readable logs.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

import yaml

from scripts.ci_cd.domain_cli import (
    branch_name_arg_type,
    domain_arg_type,
    repo_relative_file_arg_type,
)
from scripts.governance_metadata_validation.pii_privacy_checks import (
    REPO_ROOT,
    catalog_classification_for,
    index_customer_privacy_entities,
    iter_privacy_entities_from_metadata,
    list_all_metadata_paths,
    load_anonymization_controls,
    load_pii_catalog,
    validate_controls_against_privacy_index,
    validate_metadata_privacy,
)
from scripts.services.git_service import GitService
from scripts.services.metadata_file_service import MetadataFileService

SKIP_LIST_PATH = Path(__file__).parent / "skip_list.yml"
SKIP_LIST_PATH_REGEX = re.compile(r"(?:.*/)?dags/(?P<path>.*)")

metadata_file_service = MetadataFileService()


def _load_skip_list() -> set:
    with open(SKIP_LIST_PATH, encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    return set(data.get("metadata_files_out_of_pattern", []))


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--domain", type=domain_arg_type, default=None)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-f", "--file", type=repo_relative_file_arg_type)
    group.add_argument("-b", "--branch", type=branch_name_arg_type)
    group.add_argument("-a", "--all-files", action="store_true")
    args = parser.parse_args()
    if args.file:
        return (
            "file",
            args.file,
            args.verbose,
            domain_arg_type(args.domain) if args.domain else None,
        )
    if args.branch is not None:
        return (
            "branch",
            args.branch,
            args.verbose,
            domain_arg_type(args.domain) if args.domain else None,
        )
    return (
        "all_files",
        True,
        args.verbose,
        domain_arg_type(args.domain) if args.domain else None,
    )


def get_metadata_file_paths(mode, input_value, domain=None):
    files = []
    if mode == "file":
        files = [(repo_relative_file_arg_type(input_value), "A")]
    elif mode == "all_files":
        files = metadata_file_service.list_metadata_files()
    else:
        git_service = GitService()
        branch = input_value
        if not branch:
            branch = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
            ).strip()
        branch = branch_name_arg_type(branch)
        from_branch = "HEAD~1" if branch == "master" else "origin/master"
        files = [
            (file_path, status)
            for file_path, status in git_service.get_modified_files_from_diff(
                from_branch, "HEAD"
            ).items()
            if status in GitService.UPSERT_STATUS_CODES
        ]
    result = list(metadata_file_service.filter_metadata_files(files))
    if domain:
        domain_prefix = f"dags/{domain}/"
        result = [(f, s) for f, s in result if f.startswith(domain_prefix)]
    return result


def remove_prefix(input_string: str) -> str:
    return re.match(SKIP_LIST_PATH_REGEX, input_string).groupdict()["path"]


def _controls_changed_in_diff(from_branch: str, to_branch: str) -> bool:
    git_service = GitService()
    modified = git_service.get_modified_files_from_diff(from_branch, to_branch)
    prefix = "governance/pii_anonymization_controls/"
    return any(
        path.startswith(prefix) and status in GitService.UPSERT_STATUS_CODES
        for path, status in modified.items()
    )


def main():
    mode, input_value, verbose, domain = parse_args()
    skip_list = _load_skip_list()
    catalog = load_pii_catalog()
    catalog_types = set(catalog.get("types", {}).keys())
    controls = load_anonymization_controls()
    metadata_files = get_metadata_file_paths(mode, input_value, domain=domain)
    errors: list = []
    passed = []
    skipped = []
    tier_notes: list = []

    for file_path, _status in metadata_files:
        if remove_prefix(file_path) in skip_list:
            skipped.append(file_path)
            continue
        with open(REPO_ROOT / file_path, encoding="utf-8") as handle:
            metadata = yaml.safe_load(handle) or {}
        file_errors = validate_metadata_privacy(metadata, catalog_types)
        if file_errors:
            errors.extend(f"{file_path}: {err}" for err in file_errors)
        else:
            passed.append(file_path)
        if verbose:
            for id_entity, _col, privacy in iter_privacy_entities_from_metadata(
                metadata
            ):
                pii_type = privacy.get("piiType")
                if pii_type:
                    tier = catalog_classification_for(pii_type, catalog)
                    tier_notes.append(
                        f"{file_path} {id_entity}: piiType={pii_type} "
                        f"catalog.classification={tier}"
                    )

    run_controls_check = mode == "all_files"
    if mode == "branch":
        branch = (
            input_value
            or subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
            ).strip()
        )
        from_branch = (
            "HEAD~1" if branch_name_arg_type(branch) == "master" else "origin/master"
        )
        run_controls_check = _controls_changed_in_diff(from_branch, "HEAD")

    if controls and run_controls_check:
        privacy_index = index_customer_privacy_entities(list_all_metadata_paths())
        errors.extend(validate_controls_against_privacy_index(controls, privacy_index))

    if verbose:
        print(f"passed={len(passed)} skipped={len(skipped)}")
        if tier_notes:
            print("Derived catalog tiers (informational):")
            for note in tier_notes:
                print(f"  {note}")
    if errors:
        print("PII privacy validation errors:")
        for err in errors:
            print(f"  - {err}")
        raise SystemExit(1)
    print("Result: PII privacy validation passed.")


if __name__ == "__main__":
    main()
