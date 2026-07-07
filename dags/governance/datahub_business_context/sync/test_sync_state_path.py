"""Unit tests for _resolve_state_path in sync_tars_entities."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Make the parent package importable from pytest (no Airflow bootstrap needed).
_PARENT = Path(__file__).resolve().parent.parent
if str(_PARENT) not in sys.path:
    sys.path.insert(0, str(_PARENT))

from sync_tars_entities import _resolve_state_path  # noqa: E402


class TestResolveStatePath:
    def test_uses_env_var_directory(self, tmp_path):
        with pytest.MonkeyPatch().context() as mp:
            mp.setenv("TARS_SYNC_STATE_PATH", str(tmp_path))
            mp.delenv("DATABRICKS_RUNTIME_VERSION", raising=False)
            result = _resolve_state_path()
        assert result.parent == tmp_path
        assert result.name == ".tars_entity_sync_state.json"

    def test_uses_env_var_full_path(self, tmp_path):
        full = tmp_path / "custom_state.json"
        with pytest.MonkeyPatch().context() as mp:
            mp.setenv("TARS_SYNC_STATE_PATH", str(full))
            mp.delenv("DATABRICKS_RUNTIME_VERSION", raising=False)
            result = _resolve_state_path()
        assert result == full

    def test_uses_dbfs_on_databricks(self):
        with pytest.MonkeyPatch().context() as mp:
            mp.setenv("DATABRICKS_RUNTIME_VERSION", "13.0")
            mp.setenv("TARS_SYNC_STATE_PATH", "")
            result = _resolve_state_path()
        assert str(result).startswith("/dbfs/tmp/governance")

    def test_default_is_script_parent(self):
        with pytest.MonkeyPatch().context() as mp:
            mp.setenv("TARS_SYNC_STATE_PATH", "")
            mp.delenv("DATABRICKS_RUNTIME_VERSION", raising=False)
            result = _resolve_state_path()
        assert result.name == ".tars_entity_sync_state.json"
