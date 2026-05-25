"""
User-facing stdout for source-layer policy validation (banners, grouped violations).
"""

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
    print(f"DAG: {dag_name}")
    print("DAG Layer: {}".format((workflow_layer or "").upper()))
    print(f"Allowed layers: {format_allowed_layers_line(allowed_layers)}")
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
        print(f"Table with error: {path}")
        for fqn, lyr in violations_by_file[path]:
            print(f"- {fqn} (layer: {lyr})")
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


CORE_COVERAGE_POINTER = "Use the Core Model output column instead of reading directly from the clean source."


def _print_core_coverage_violations(
    violations_by_file: Mapping[str, List[Tuple[str, str, str]]],
) -> None:
    for path in sorted(violations_by_file.keys()):
        print(f"File: {path}")
        for output_col, clean_lineage, core_fqn in violations_by_file[path]:
            print(
                f"- Column `{output_col}` has lineage from `{clean_lineage}`, which is already covered"
                f" by Core Model as `{core_fqn}`. Use the Core Model output instead."
            )
        print("")


def print_core_coverage_failure_opening(
    dag_name: str,
    violations_by_file: Mapping[str, List[Tuple[str, str, str]]],
) -> None:
    print("")
    print_separator()
    print("")
    print("❌ Core Model coverage check failed.")
    print(
        "   New metadata file(s) declare lineage from clean source columns that are"
        " already modelled by a Core Model."
    )
    print("")
    print(f"DAG: {dag_name}")
    print_separator()
    print("")
    _print_core_coverage_violations(violations_by_file)


def print_core_coverage_failure_footer() -> None:
    print(RESOLVE_LINE)
    print("")
    print(CORE_COVERAGE_POINTER)
    print("")
    print_separator()


def print_core_coverage_warning_opening(
    dag_name: str,
    violations_by_file: Mapping[str, List[Tuple[str, str, str]]],
) -> None:
    print("")
    print_separator()
    print(
        "⚠️ Core Model coverage warning: existing metadata file(s) declare lineage"
        " from clean source columns already modelled by a Core Model."
    )
    print("")
    print(f"DAG: {dag_name}")
    print_separator()
    print("")
    _print_core_coverage_violations(violations_by_file)


def print_core_coverage_warning_footer() -> None:
    print(CORE_COVERAGE_POINTER)
    print("")
    print_separator()
