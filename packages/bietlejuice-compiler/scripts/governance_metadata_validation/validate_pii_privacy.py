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
from scripts.governance_metadata_validation.lineage_privacy_validator import (
    validate_lineage_privacy_for_files,
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
from scripts.governance_metadata_validation.pii_privacy_report import (
    format_tier_note,
    print_no_files_in_scope,
    print_report,
    print_scope_header,
    relative_repo_path,
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


def branch_from_ref(branch: str) -> str:
    if not branch:
        branch = subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
        ).strip()
    return branch_name_arg_type(branch)


def diff_from_branch(branch: str) -> str:
    branch = branch_from_ref(branch)
    return "HEAD~1" if branch == "master" else "origin/master"


def get_metadata_file_paths(mode, input_value, domain=None):
    files = []
    if mode == "file":
        files = [(repo_relative_file_arg_type(input_value), "A")]
    elif mode == "all_files":
        files = metadata_file_service.list_metadata_files()
    else:
        git_service = GitService()
        from_branch = diff_from_branch(input_value)
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


def controls_changed_for_branch(branch: str) -> bool:
    from_branch = diff_from_branch(branch)
    return _controls_changed_in_diff(from_branch, "HEAD")


def main():
    mode, input_value, verbose, domain = parse_args()
    branch_label = branch_from_ref(input_value) if mode == "branch" else None
    skip_list = _load_skip_list()
    catalog = load_pii_catalog()
    catalog_types = set(catalog.get("types", {}).keys())
    controls = load_anonymization_controls()
    metadata_files = get_metadata_file_paths(mode, input_value, domain=domain)
    run_controls_check = mode == "all_files"
    if mode == "branch":
        run_controls_check = controls_changed_for_branch(input_value)

    if not metadata_files and not run_controls_check:
        print_no_files_in_scope(domain=domain)
        return

    print_scope_header(
        branch=branch_label,
        domain=domain,
        file_count=len(metadata_files),
    )

    errors: list = []
    warnings: list = []
    passed = []
    skipped = []
    tier_notes: list = []
    all_metadata_paths = list_all_metadata_paths()
    lineage_check_paths: list[Path] = []

    for file_path, _status in metadata_files:
        if remove_prefix(file_path) in skip_list:
            skipped.append(file_path)
            continue
        with open(REPO_ROOT / file_path, encoding="utf-8") as handle:
            metadata = yaml.safe_load(handle) or {}
        file_errors = validate_metadata_privacy(metadata, catalog_types)
        if file_errors:
            errors.extend(
                f"{relative_repo_path(file_path)}: {err}" for err in file_errors
            )
        else:
            passed.append(file_path)
        if metadata.get("privacy") or any(
            isinstance(col, dict) and col.get("privacy")
            for col in (metadata.get("columns") or {}).values()
        ):
            lineage_check_paths.append(REPO_ROOT / file_path)
        if verbose:
            for id_entity, _col, privacy in iter_privacy_entities_from_metadata(
                metadata
            ):
                pii_type = privacy.get("piiType")
                if pii_type:
                    tier = catalog_classification_for(pii_type, catalog)
                    tier_notes.append(
                        format_tier_note(file_path, id_entity, pii_type, tier)
                    )

    if controls and run_controls_check:
        privacy_index = index_customer_privacy_entities(all_metadata_paths)
        errors.extend(validate_controls_against_privacy_index(controls, privacy_index))

    if lineage_check_paths:
        lineage_errors, lineage_warnings = validate_lineage_privacy_for_files(
            lineage_check_paths, all_metadata_paths
        )
        if mode == "branch":
            errors.extend(lineage_errors)
        else:
            warnings.extend(lineage_errors)
        warnings.extend(lineage_warnings)

    print_report(
        passed=passed,
        skipped=skipped,
        warnings=warnings,
        errors=errors,
        tier_notes=tier_notes,
        verbose=verbose,
    )
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
