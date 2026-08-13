"""Tests for bootstrap orphan-delete SQL wiring in the shared loader."""

from __future__ import annotations

import importlib.util
from pathlib import Path

_REPO = Path(__file__).resolve().parents[7]
_JOB = (
    _REPO
    / "dags"
    / "cross"
    / "base"
    / "spark_jobs"
    / "load_milestone_dimension.py"
)
_spec = importlib.util.spec_from_file_location("load_milestone_dimension", _JOB)
_mod = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(_mod)
_sql_string_list = _mod._sql_string_list


def test_sql_string_list_escapes_quotes():
    assert _sql_string_list(["first_vb"]) == "'first_vb'"
    assert _sql_string_list(["a", "b'c"]) == "'a', 'b''c'"


def test_bootstrap_orphan_delete_condition_shape():
    bootstrap_types = ["first_vb", "first_vc"]
    delete_orphans = f"target.milestone_type IN ({_sql_string_list(bootstrap_types)})"
    assert delete_orphans == "target.milestone_type IN ('first_vb', 'first_vc')"
    assert _sql_string_list([]) == ""
