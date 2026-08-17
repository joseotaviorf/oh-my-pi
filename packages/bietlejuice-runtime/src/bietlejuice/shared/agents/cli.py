"""Positional Spark CLI parser for agent-domain jobs.

Airflow / Databricks pass job args as positional strings. This helper builds
an ``ArgumentParser`` from an ``(name, type, default, help)`` spec, appends
validation-target flags, and ignores unknown extras.

Callers own the spec (DAG name, table, extra knobs). This module does not.
"""

from __future__ import annotations

from argparse import ArgumentParser, Namespace
from typing import Callable, Sequence, Tuple, Union

from bietlejuice.base.validation.spark_args import add_validation_target_args

ArgDefault = Union[object, Callable[[], object]]
ArgSpec = Tuple[str, type, ArgDefault, str]


def _default_values(arg_spec: Sequence[ArgSpec]) -> list:
    return [
        default() if callable(default) else default for _, _, default, _ in arg_spec
    ]


def parse_args(
    job_name: str,
    arg_spec: Sequence[ArgSpec],
) -> Namespace:
    """Parse positional Spark job args plus optional validation write-target flags."""
    parser = ArgumentParser(description=job_name)
    default_values = _default_values(arg_spec)
    for (name, type_, _default, help_text), default_val in zip(
        arg_spec, default_values
    ):
        parser.add_argument(
            name, nargs="?", type=type_, default=default_val, help=help_text
        )
    add_validation_target_args(parser)
    namespace, _ = parser.parse_known_args()
    return namespace
