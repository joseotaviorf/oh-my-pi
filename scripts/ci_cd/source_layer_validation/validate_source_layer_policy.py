#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PR-scoped validation: referenced tables must belong to layers allowed for the DAG
output layer (from ``workflow.layer`` in the declaration).

- **Strict (exit 1):** PR adds a new DAG declaration or new source files
  (``queries/**/*.sql``, ``spark_jobs`` SQL/YAML/Py) under a DAG — violations in
  those new files fail CI.
- **Lenient (exit 0 + warnings):** PR only modifies existing files or non-source
  paths — full DAG is scanned; violations are warnings only.

CI uses profile ``dags`` (``profiles/dags.yml``), path_prefix ``dags/``.
"""

from __future__ import print_function

import argparse
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import yaml

# Repo root on path (Makefile uses PYTHONPATH=.)
from scripts.services.git_service import GitService

from scripts.ci_cd.source_layer_validation.dag_reference_extractors import (
    _normalize_repo_rel_path,
    extract_tables_by_source_file,
)
from scripts.ci_cd.source_layer_validation import output_messages
from scripts.ci_cd.source_layer_validation.dag_source_paths import (
    dag_requires_strict_validation,
    list_added_source_artifacts,
)
from scripts.ci_cd.source_layer_validation.layer_classifier import (
    classify_table_fqn,
    is_layer_allowed,
)
from scripts.ci_cd.source_layer_validation.layer_policy_matrix import (
    allowed_layers_for_output,
)
from scripts.ci_cd.source_layer_validation.read_dag_declaration import (
    get_workflow_layer_and_type,
)


def load_profile(cli_profile_name: str) -> Dict[str, Any]:
    """Load profiles/<file>.yml where cli_profile matches."""
    prof_dir = Path(__file__).resolve().parent / "profiles"
    for path in sorted(prof_dir.glob("*.yml")):
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        if not data:
            continue
        if data.get("cli_profile") == cli_profile_name:
            data["_profile_file"] = str(path)
            return data
    sys.stderr.write(
        "Unknown profile {!r}. Add profiles/*.yml with matching cli_profile.\n".format(
            cli_profile_name
        )
    )
    sys.exit(2)


def dag_roots_from_changed_files(
    changed_paths: List[str], profile: Dict[str, Any]
) -> List[str]:
    """Paths under path_prefix -> unique dag root dirs (first N segments)."""
    prefix = profile["path_prefix"]
    n = int(profile["dag_root_segment_count"])
    roots = set()
    for path in changed_paths:
        if not path.startswith(prefix):
            continue
        parts = path.split("/")
        if len(parts) >= n:
            roots.add("/".join(parts[:n]))
    return sorted(roots)


def is_valid_dag_root(dag_root_str: str) -> bool:
    """Folder must contain ``{folder}_declaration.yml``."""
    p = Path(dag_root_str)
    if not p.is_dir():
        return False
    decl = p / "{}_declaration.yml".format(p.name)
    return decl.is_file()


def is_valid_core_spark_dag_root(dag_root_str: str) -> bool:
    """Backward-compatible alias for tests; same as ``is_valid_dag_root``."""
    return is_valid_dag_root(dag_root_str)


def get_branch_mode_affected_roots(
    changed_files_dict: Dict[str, str], profile: Dict[str, Any]
) -> Tuple[Optional[str], List[str]]:
    """
    DAG roots with at least one added/modified file under path_prefix.

    Returns:
        (skip_reason, dag_roots): if skip_reason is not None, exit 0 without
        validating; otherwise dag_roots is non-empty list to validate.
    """
    prefix = profile["path_prefix"]
    upsert = [
        p
        for p, st in changed_files_dict.items()
        if st in GitService.UPSERT_STATUS_CODES
    ]
    touched = [p for p in upsert if p.startswith(prefix)]
    if not touched:
        return (
            "No changes under {} — skipping source-layer policy check.".format(prefix),
            [],
        )
    dag_roots = dag_roots_from_changed_files(touched, profile)
    dag_roots = [r for r in dag_roots if is_valid_dag_root(r)]
    if not dag_roots:
        return (
            "No DAG declaration folders affected under {} — skipping.".format(prefix),
            [],
        )
    return None, dag_roots


def find_all_dag_roots() -> List[str]:
    """Every ``dags/<domain>/<name>/`` with a declaration file."""
    roots = []
    dags = Path("dags")
    if not dags.is_dir():
        return roots
    for domain_dir in sorted(dags.iterdir()):
        if not domain_dir.is_dir() or domain_dir.name.startswith("."):
            continue
        for dag_dir in sorted(domain_dir.iterdir()):
            if dag_dir.is_dir() and is_valid_dag_root(str(dag_dir)):
                roots.append(str(dag_dir))
    return sorted(roots)


def _violations_by_source_file(
    tables_by_file: Dict[str, Set[str]], allowed_layers: Iterable[str]
) -> Dict[str, List[Tuple[str, str]]]:
    """repo_rel_path -> list of (fqn, LAYER_UPPER) disallowed refs."""
    allowed_list = list(allowed_layers)
    out: Dict[str, List[Tuple[str, str]]] = {}
    for rel_path in sorted(tables_by_file.keys()):
        viols = []
        for t in sorted(tables_by_file[rel_path]):
            classified = classify_table_fqn(t)
            if not classified:
                continue
            fqn, lyr, _schema = classified
            if lyr == "unknown":
                continue
            if not is_layer_allowed(lyr, allowed_list):
                viols.append((fqn, lyr.upper()))
        if viols:
            out[rel_path] = viols
    return out


def run_validation(
    dag_roots: List[str],
    profile: Dict[str, Any],
    verbose: bool,
    changed_files: Optional[Dict[str, str]],
) -> Tuple[bool, bool]:
    """
    Returns (strict_ok, had_warnings_printed).

    strict_ok is False when new source artifacts violate policy. Warnings do not
    set strict_ok to False.
    """
    changed_files = changed_files or {}
    profile_id = profile.get("id", "unknown")
    skip_types = {x.lower() for x in (profile.get("skip_workflow_types") or []) if x}

    any_strict_fail = False
    had_warnings = False

    for dag_root in dag_roots:
        dag_name = Path(dag_root).name
        dr = Path(dag_root)
        layer, wtype = get_workflow_layer_and_type(dr)

        if wtype and wtype.lower() in skip_types:
            if verbose:
                print("")
                print(
                    "DAG: {} (profile {}) — skipped (workflow.type {!r}).".format(
                        dag_name, profile_id, wtype
                    )
                )
            continue

        allowed = allowed_layers_for_output(layer) if layer else None
        if allowed is None:
            if verbose:
                print("")
                print(
                    "DAG: {} (profile {}) — skipped (missing workflow.layer: {!r}).".format(
                        dag_name, profile_id, layer
                    )
                )
            continue

        strict = dag_requires_strict_validation(dag_root, changed_files)
        tables_by_file = extract_tables_by_source_file(profile, dr, wtype)
        violations_by_path = _violations_by_source_file(tables_by_file, allowed)

        added_paths = list_added_source_artifacts(dag_root, changed_files)
        added_set = {_normalize_repo_rel_path(p) for p in added_paths}

        violations_new = {
            k: violations_by_path[k]
            for k in violations_by_path
            if _normalize_repo_rel_path(k) in added_set
        }
        violations_pre = {
            k: violations_by_path[k]
            for k in violations_by_path
            if _normalize_repo_rel_path(k) not in added_set
        }

        if verbose and violations_by_path:
            print("")
            print("DAG: {} (profile {})".format(dag_name, profile_id))
            print(
                "  Mode: {}".format(
                    "strict (new DAG or new source files)"
                    if strict
                    else "lenient (warnings only)"
                )
            )
            print("  workflow.layer={!r} workflow.type={!r}".format(layer, wtype))
            print("  Files with policy violations: {}".format(len(violations_by_path)))

        if strict and violations_new:
            any_strict_fail = True
            output_messages.print_validation_failure_opening(
                dag_name, layer or "", allowed
            )
            output_messages.print_grouped_invalid_table_usage(
                "Invalid table usage in **new** files:",
                violations_new,
            )
            output_messages.print_failure_footer()
            if violations_pre:
                had_warnings = True
                output_messages.print_validation_warning_opening(
                    dag_name, layer or "", allowed
                )
                output_messages.print_grouped_invalid_table_usage(
                    "Invalid table usage in **edited** files:",
                    violations_pre,
                )
                output_messages.print_warning_footer()
        elif strict and violations_pre and not violations_new:
            had_warnings = True
            output_messages.print_validation_warning_opening(
                dag_name, layer or "", allowed
            )
            output_messages.print_grouped_invalid_table_usage(
                "Invalid table usage in **edited** files:",
                violations_pre,
            )
            output_messages.print_warning_footer()
        elif not strict and violations_by_path:
            had_warnings = True
            output_messages.print_validation_warning_opening(
                dag_name, layer or "", allowed
            )
            output_messages.print_grouped_invalid_table_usage(
                "Invalid table usage in **edited** files:",
                violations_by_path,
            )
            output_messages.print_warning_footer()

    return not any_strict_fail, had_warnings


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate source table layers for changed DAGs (profile-based)."
    )
    parser.add_argument(
        "--profile",
        default="dags",
        help="Profile cli_profile from profiles/*.yml (default: dags)",
    )
    parser.add_argument(
        "-b",
        "--branch",
        help="Branch name; diff against origin/master (or HEAD~1 on master)",
    )
    parser.add_argument(
        "-a",
        "--all-dags",
        action="store_true",
        help="Validate every DAG under dags/ (local audit)",
    )
    parser.add_argument(
        "--core-only",
        action="store_true",
        help="With -a, restrict audit to dags/core/ only",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    profile = load_profile(args.profile)

    changed_files = None
    if args.all_dags:
        dag_roots = find_all_dag_roots()
        if args.core_only:
            dag_roots = [r for r in dag_roots if r.startswith("dags/core/")]
        if not dag_roots:
            print("No DAG roots found under dags/")
            sys.exit(0)
        if args.verbose:
            print(
                "Validating all {} DAG(s) (profile: {})".format(
                    len(dag_roots), args.profile
                )
            )
    else:
        branch = args.branch
        if branch is None:
            parser.error("Provide -b BRANCH or use -a/--all-dags")

        git_service = GitService()
        if branch == "master":
            from_branch = "HEAD~1"
        else:
            from_branch = "origin/master"
            git_service.fetch("master")

        changed_files = git_service.get_modified_files_from_diff(from_branch, "HEAD")
        skip_reason, dag_roots = get_branch_mode_affected_roots(changed_files, profile)
        if skip_reason is not None:
            print(skip_reason)
            sys.exit(0)

        if args.verbose:
            prefix = profile["path_prefix"]
            touched = [
                p
                for p, st in changed_files.items()
                if st in GitService.UPSERT_STATUS_CODES and p.startswith(prefix)
            ]
            branch_display = branch if branch else "(unset)"
            print(
                "Branch {!r}: {} file(s) under {}, {} DAG(s) to validate.".format(
                    branch_display, len(touched), profile["path_prefix"], len(dag_roots)
                )
            )

    # Audit mode (-a): strict rules would require synthetic changed_files; treat as lenient
    if args.all_dags:
        changed_files = {}

    ok, had_warnings = run_validation(dag_roots, profile, args.verbose, changed_files)
    if ok:
        if had_warnings:
            output_messages.print_source_validation_final_pass_after_warnings()
        else:
            output_messages.print_source_validation_clean_success()
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()
