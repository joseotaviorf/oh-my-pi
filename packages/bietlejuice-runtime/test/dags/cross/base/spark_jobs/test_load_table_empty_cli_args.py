"""Argparse tests for load_table_* CLI None sentinel (schema/tree_path slots)."""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[7]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

for _mod in (
    "quintoandar_logger",
    "bietlejuice.base.databricks.table_privileges",
    "bietlejuice.base.db.datalake_metastore_service",
    "bietlejuice.base.db.metric_metastore_mapping",
    "bietlejuice.base.service.dag_packages_path_service",
    "bietlejuice.base.spark.runtime_detector",
    "bietlejuice.pipeline.full_table_loader_pipeline",
    "bietlejuice.pipeline.incremental_table_loader_pipeline",
):
    sys.modules.setdefault(_mod, MagicMock())

from dags.cross.base.spark_jobs.load_table_full import (  # noqa: E402
    build_arg_parser as build_load_table_full_parser,
)
from dags.cross.base.spark_jobs.load_table_incremental import (  # noqa: E402
    build_arg_parser as build_load_table_incremental_parser,
)

LOAD_TABLE_BASE_ARGV = [
    "forno",
    "prod-datalake",
    "clean",
    "gsheets",
    "gsheets",
    "gsheets_agents",
    "agents",
    "[]",
    "2026-08-24",
    "{}",
    "{}",
]


@pytest.mark.parametrize(
    "build_parser",
    [build_load_table_full_parser, build_load_table_incremental_parser],
)
def test_load_table_none_sentinel_decodes_both_slots(build_parser):
    args = build_parser().parse_args(LOAD_TABLE_BASE_ARGV + ["None", "None"])
    assert args.schema is None
    assert args.tree_path is None


@pytest.mark.parametrize(
    "build_parser",
    [build_load_table_full_parser, build_load_table_incremental_parser],
)
def test_load_table_empty_strings_still_map_to_none(build_parser):
    args = build_parser().parse_args(LOAD_TABLE_BASE_ARGV + ["", ""])
    assert args.schema is None
    assert args.tree_path is None


@pytest.mark.parametrize(
    "build_parser",
    [build_load_table_full_parser, build_load_table_incremental_parser],
)
def test_load_table_none_sentinel_preserves_second_slot(build_parser):
    args = build_parser().parse_args(LOAD_TABLE_BASE_ARGV + ["None", "my_tree"])
    assert args.schema is None
    assert args.tree_path == "my_tree"


@pytest.mark.parametrize(
    "build_parser",
    [build_load_table_full_parser, build_load_table_incremental_parser],
)
def test_load_table_real_values_bind_to_correct_slots(build_parser):
    args = build_parser().parse_args(LOAD_TABLE_BASE_ARGV + ["my_schema", "my_tree"])
    assert args.schema == "my_schema"
    assert args.tree_path == "my_tree"
