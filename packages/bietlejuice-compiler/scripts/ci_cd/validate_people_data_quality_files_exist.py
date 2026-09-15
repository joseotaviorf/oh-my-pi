"""Ensure scoped pipeline queries have a matching data_quality YAML (clean+ layers).

Mirrors ``validate_metadata_files_exist`` but for ``data_quality/{layer}/{table}.yml``
under ``dags/people/**`` and ``dags/enterprise_efficiency/**``. Layers ``raw`` and
``reverse`` are excluded.

Problem: modeled tables ship without Inmetro configs, so data issues reach
consumers before anyone notices. This gate fails the PR when a new or changed
query/metadata file has no sibling DQ YAML.

Usage (CI):
    python validate_people_data_quality_files_exist.py -b "$CI_COMMIT_BRANCH"

Usage (audit all scoped query tables):
    python validate_people_data_quality_files_exist.py -a
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from scripts.ci_cd.domain_cli import (
    branch_name_arg_type,
    repo_relative_file_arg_type,
)
from scripts.ci_cd.people_domain_scope import (
    DOMAIN_FOLDER_NAMES,
    DQ_REQUIRED_LAYERS,
    SCOPE_PATHS_HELP,
    dq_path_for_artifact,
    is_scoped_domain_path,
    iter_scoped_domain_roots,
    normalize_path,
    requires_dq_file,
)
from scripts.governance_metadata_validation.validate_metadata_files_exist import (
    get_query_file_paths,
)
from scripts.services.git_service import GitService


def _metadata_paths_from_diff(branch: str) -> List[str]:
    """Collect changed metadata YAML paths under scoped domains from the branch diff.

    Query SQL changes are discovered via ``get_query_file_paths``; metadata-only
    edits (e.g. column descriptions) also require a DQ file and must be included.
    """
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    paths: List[str] = []
    for filepath, status in git_service.get_modified_files_from_diff(
        from_ref, "HEAD"
    ).items():
        if status not in git_service.UPSERT_STATUS_CODES:
            continue
        normalized = normalize_path(filepath)
        if is_scoped_domain_path(normalized) and "/metadata/" in normalized:
            paths.append(filepath)
    return paths


def collect_artifact_paths(
    mode: str,
    input_value: str | bool,
    paths: Optional[Sequence[str]] = None,
) -> List[str]:
    """Build the list of query/metadata artifacts to check for DQ pairing.

    Modes: explicit ``--paths``, full-repo audit (``all_files``), branch diff,
    or a single file path. Skips layers outside ``DQ_REQUIRED_LAYERS`` later via
    ``requires_dq_file``.
    """
    if paths:
        result: List[str] = []
        for raw in paths:
            path = Path(raw)
            if not is_scoped_domain_path(str(path)):
                raise SystemExit(
                    f"error: --paths must be under {SCOPE_PATHS_HELP}: {raw}"
                )
            if path.is_dir():
                for child in sorted(path.rglob("*")):
                    if child.is_file() and child.suffix in {".sql", ".yml"}:
                        result.append(str(child).replace("\\", "/"))
            elif path.is_file():
                result.append(str(path).replace("\\", "/"))
        return result

    if mode == "all_files":
        artifacts: List[str] = []
        for root in iter_scoped_domain_roots():
            for layer in DQ_REQUIRED_LAYERS:
                for sql_path in root.rglob(f"queries/{layer}/*.sql"):
                    artifacts.append(str(sql_path).replace("\\", "/"))
                for meta_path in root.rglob(f"metadata/{layer}/*.yml"):
                    artifacts.append(str(meta_path).replace("\\", "/"))
        return sorted(set(artifacts))

    if mode == "branch":
        artifacts: List[str] = []
        for domain in DOMAIN_FOLDER_NAMES:
            query_files = get_query_file_paths("branch", input_value, domain=domain)
            artifacts.extend([file for file, _ in query_files])
        artifacts.extend(_metadata_paths_from_diff(str(input_value)))
        return sorted(set(artifacts))

    if mode == "file":
        return [repo_relative_file_arg_type(str(input_value))]

    return []


def parse_args() -> argparse.Namespace:
    """Parse CLI flags: branch diff, full audit, or explicit scoped paths."""
    parser = argparse.ArgumentParser(
        description="Validate scoped query/metadata artifacts have data_quality YAML."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", type=branch_name_arg_type)
    group.add_argument("-a", "--all-files", action="store_true")
    group.add_argument(
        "--paths",
        nargs="+",
        type=repo_relative_file_arg_type,
        help=f"Scoped DAG paths under {SCOPE_PATHS_HELP}",
    )
    return parser.parse_args()


def main() -> int:
    """Verify each modeled artifact has ``data_quality/{layer}/{table}.yml``; exit 1 if missing."""
    args = parse_args()

    if args.paths:
        artifacts = collect_artifact_paths("paths", True, paths=args.paths)
    elif args.all_files:
        artifacts = collect_artifact_paths("all_files", True)
    else:
        branch = args.branch
        if not branch:
            branch = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
            ).strip()
        artifacts = collect_artifact_paths("branch", branch)

    checked: List[str] = []
    skipped: List[str] = []
    missing: List[Tuple[str, str]] = []

    for artifact in artifacts:
        if not requires_dq_file(artifact):
            skipped.append(artifact)
            continue
        dq_path = dq_path_for_artifact(artifact)
        if dq_path is None:
            skipped.append(artifact)
            continue
        checked.append(artifact)
        if not dq_path.is_file():
            missing.append((artifact, str(dq_path)))

    print(f"Checked {len(checked)} scoped artifact(s) for data_quality pairing\n")
    if missing:
        print("Artifacts without a corresponding data_quality file:")
        for artifact, dq_path in missing:
            print(f"  {artifact}")
            print(f"    expected: {dq_path}")
            print(
                "    → Fix: create that YAML with `table_name`, `alert_channel: PEOPLE_ALERTS`, "
                "`table_level_validations.has_size` (greater_than: 1, Error), and on clean "
                "layers `has_size_variation` (Error, -10 / +25). "
                "Copy a sibling table in the same DAG as a template."
            )
        print()
    if skipped:
        print(f"Skipped {len(skipped)} file(s) (out of scope or raw/reverse layer)\n")

    if args.paths:
        if not artifacts:
            print(
                "error: --paths did not match any .sql or .yml files under scoped DAG roots.",
                file=sys.stderr,
            )
            return 1
        if not checked:
            print(
                "error: --paths did not include any clean/enrich/dw/metric query or "
                "metadata files to validate (raw/reverse layers are excluded).",
                file=sys.stderr,
            )
            return 1

    if not checked and not args.all_files and not args.paths and args.branch:
        print(
            "No changed scoped query/metadata files in clean+ layers — nothing to validate."
        )
        return 0

    if missing:
        print(
            "Result: Some tables do not have corresponding data_quality files.\n"
            "How to fix:\n"
            "  • Add data_quality/{layer}/{table}.yml next to the query/metadata file "
            "(clean, enrich, dw, metric only; raw and reverse are excluded).\n"
            "  • Local rerun: make validate-people-data-quality-files-exist "
            "paths=dags/people/<dag>\n"
            "  • DQ content rules: .cursor/rules/people/people_data_quality.mdc"
        )
        return 1

    print("Result: All checked artifacts have a corresponding data_quality file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
