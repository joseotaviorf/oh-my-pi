# -*- coding: utf-8 -*-
"""
User-facing stdout for source-layer policy validation (banners, grouped violations).
"""

from __future__ import print_function

from typing import Iterable, List, Mapping, Tuple

SEPARATOR = "=" * 72

MATRIX_POINTER = (
    "Check the allowed layers in scripts/ci_cd/source_layer_validation/"
    "layer_policy_matrix.py – ALLOWED_SOURCE_LAYERS_BY_OUTPUT."
)

RESOLVE_LINE = "Resolve the issue(s) above to enable merging!"


def print_separator():
    print(SEPARATOR)


def print_source_validation_clean_success():
    print_separator()
    print("✅ Source validation passed!")
    print_separator()


def print_source_validation_final_pass_after_warnings():
    """Short closing line after warning blocks (exit 0, merge not blocked)."""
    print("✅ Source validation passed (with warnings above).")


def format_allowed_layers_line(allowed_layers: Iterable[str]) -> str:
    parts = sorted(x.upper() for x in allowed_layers)
    return ", ".join(parts)


def _print_dag_context(
    dag_name: str, workflow_layer: str, allowed_layers: Iterable[str]
) -> None:
    print("DAG: {}".format(dag_name))
    print("DAG Layer: {}".format((workflow_layer or "").upper()))
    print("Allowed layers: {}".format(format_allowed_layers_line(allowed_layers)))
    print("")


def print_validation_failure_opening(
    dag_name: str, workflow_layer: str, allowed_layers: Iterable[str]
) -> None:
    print("")
    print_separator()
    print("")
    print("❌ Source validation failed in the following files")
    print("")
    _print_dag_context(dag_name, workflow_layer, allowed_layers)
    print_separator()
    print("")


def print_validation_warning_opening(
    dag_name: str, workflow_layer: str, allowed_layers: Iterable[str]
) -> None:
    print("")
    print_separator()
    print(
        "⚠️ Source validation passed with a warning in the following files "
        "(errors in pre existing files)."
    )
    _print_dag_context(dag_name, workflow_layer, allowed_layers)
    print_separator()
    print("")


def print_grouped_invalid_table_usage(
    heading: str, violations_by_file: Mapping[str, List[Tuple[str, str]]]
) -> None:
    """
    heading: e.g. "Invalid table usage in **new** files:"
    violations_by_file: repo_rel_path -> [(fqn, LAYER_UPPER), ...]
    """
    print(heading)
    print("")
    for path in sorted(violations_by_file.keys()):
        print("Table with error: {}".format(path))
        for fqn, lyr in violations_by_file[path]:
            print("- {} (layer: {})".format(fqn, lyr))
        print("")


def print_failure_footer():
    print(RESOLVE_LINE)
    print("")
    print(MATRIX_POINTER)
    print("")
    print_separator()


def print_warning_footer():
    print(MATRIX_POINTER)
    print("")
    print_separator()
