"""Argparse tests for data_quality_tests EMR None sentinel on intermediate_path."""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

_REPO_ROOT = Path(__file__).resolve().parents[7]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

for _mod in (
    "quintoandar_logger",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.base.spark.runtime_detector",
    "bietlejuice.pipeline.data_quality_tests_pipeline",
    "bietlejuice.services.configuration_service",
):
    sys.modules.setdefault(_mod, MagicMock())

from dags.cross.base.spark_jobs import data_quality_tests  # noqa: E402

DQ_BASE_ARGV = [
    "data_quality_tests",
    "forno",
    "2026-08-24",
    "s3://inmetro",
    "clean",
    "gsheets_agents",
    "agents",
]


def test_intermediate_path_none_sentinel_decodes_to_empty():
    with patch.object(sys, "argv", DQ_BASE_ARGV + ["None"]):
        args = data_quality_tests.parse_args()
    assert args.intermediate_path == ""


def test_intermediate_path_empty_string_decodes_to_empty():
    with patch.object(sys, "argv", DQ_BASE_ARGV + [""]):
        args = data_quality_tests.parse_args()
    assert args.intermediate_path == ""


def test_intermediate_path_real_value_is_preserved():
    with patch.object(sys, "argv", DQ_BASE_ARGV + ["my_tree"]):
        args = data_quality_tests.parse_args()
    assert args.intermediate_path == "my_tree"
