"""Unit tests for _resolve_state_path in sync_tars_entities_dag."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# The DAG file is not a package, so we add its directory to sys.path and
# import the helper we need via importlib.
_DAG_DIR = Path(__file__).resolve().parents[3] / "sync_tars_entities"


def _import_resolve():
    """Import _resolve_state_path from the DAG module without triggering DAG registration."""
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "sync_tars_entities_dag",
        _DAG_DIR / "sync_tars_entities_dag.py",
    )
    # Stub heavy Airflow / bietlejuice imports so the module loads in plain pytest.
    stubs = {
        "airflow": None,
        "airflow.models": None,
        "airflow.models.param": None,
        "airflow.operators.python": None,
        "bietlejuice": None,
        "bietlejuice.base": None,
        "bietlejuice.base.airflow": None,
        "bietlejuice.base.airflow.dag_owner_enum": None,
        "pendulum": None,
    }
    import types

    for mod_name, _ in stubs.items():
        if mod_name not in sys.modules:
            sys.modules[mod_name] = types.ModuleType(mod_name)

    # Minimal stubs for used symbols
    import sys as _sys

    _sys.modules["airflow"].DAG = object
    dag_owner = types.ModuleType("bietlejuice.base.airflow.dag_owner_enum")
    dag_owner.DAGOwnerEnum = type(
        "DAGOwnerEnum", (), {"DATA_GOVERNANCE": "data_governance"}
    )
    _sys.modules["bietlejuice.base.airflow.dag_owner_enum"] = dag_owner
    _sys.modules["airflow.models"].Variable = type(
        "Variable", (), {"get": staticmethod(lambda *a, **kw: "")}
    )
    _sys.modules["airflow.models"].param = types.ModuleType("param")
    _sys.modules["airflow.models.param"].Param = object
    _sys.modules["airflow.operators.python"].PythonOperator = object
    _sys.modules["pendulum"] = type(
        "pendulum_stub", (), {"datetime": staticmethod(lambda *a, **kw: None)}
    )()

    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod._resolve_state_path


# Only run these tests if the DAG file is importable (i.e. in a uv env).
pytest.importorskip("importlib.util")

_resolve_state_path = _import_resolve()


class TestResolveStatePath:
    def test_uses_env_var_directory(self, tmp_path):
        with patch.dict(
            os.environ, {"TARS_SYNC_STATE_PATH": str(tmp_path)}, clear=False
        ):
            result = _resolve_state_path()
        assert result.parent == tmp_path
        assert result.name == ".tars_entity_sync_state.json"

    def test_uses_env_var_full_path(self, tmp_path):
        full = tmp_path / "custom_state.json"
        with patch.dict(os.environ, {"TARS_SYNC_STATE_PATH": str(full)}, clear=False):
            result = _resolve_state_path()
        assert result == full

    def test_uses_dbfs_on_databricks(self, tmp_path):
        env = {"DATABRICKS_RUNTIME_VERSION": "13.0", "TARS_SYNC_STATE_PATH": ""}
        with patch.dict(os.environ, env, clear=False):
            result = _resolve_state_path()
        assert str(result).startswith("/dbfs/tmp/governance")

    def test_default_is_script_parent(self):
        env = {"TARS_SYNC_STATE_PATH": "", "DATABRICKS_RUNTIME_VERSION": ""}
        with patch.dict(os.environ, env, clear=False):
            # Remove DATABRICKS_RUNTIME_VERSION if it exists in env
            os.environ.pop("DATABRICKS_RUNTIME_VERSION", None)
            result = _resolve_state_path()
        assert result.name == ".tars_entity_sync_state.json"
