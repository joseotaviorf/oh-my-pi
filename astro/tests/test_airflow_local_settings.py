"""Unit tests for astro/config/airflow_local_settings.py (parse pre-warm)."""

from __future__ import annotations

import importlib
import os
import sys
import types
from pathlib import Path
from unittest import mock

import pytest

CONFIG_DIR = Path(__file__).resolve().parents[1] / "config"


@pytest.fixture(scope="module")
def prewarm_mod():
    """Load airflow_local_settings without triggering import-time prewarm."""
    sys.path.insert(0, str(CONFIG_DIR))
    # Ensure a fresh load with BIETLEJUICE_PREWARM=never so import is a no-op.
    previous = os.environ.get("BIETLEJUICE_PREWARM")
    previous_declarations = os.environ.get("BIETLEJUICE_PREWARM_DECLARATIONS")
    os.environ["BIETLEJUICE_PREWARM"] = "never"
    os.environ["BIETLEJUICE_PREWARM_DECLARATIONS"] = "never"
    if "airflow_local_settings" in sys.modules:
        del sys.modules["airflow_local_settings"]
    mod = importlib.import_module("airflow_local_settings")
    yield mod
    sys.modules.pop("airflow_local_settings", None)
    if str(CONFIG_DIR) in sys.path:
        sys.path.remove(str(CONFIG_DIR))
    if previous is None:
        os.environ.pop("BIETLEJUICE_PREWARM", None)
    else:
        os.environ["BIETLEJUICE_PREWARM"] = previous
    if previous_declarations is None:
        os.environ.pop("BIETLEJUICE_PREWARM_DECLARATIONS", None)
    else:
        os.environ["BIETLEJUICE_PREWARM_DECLARATIONS"] = previous_declarations


@pytest.mark.parametrize(
    "argv,env,expected",
    [
        (["airflow", "dag-processor"], None, True),
        (["/usr/bin/airflow", "scheduler"], None, True),
        (["airflow", "webserver"], None, False),
        (["airflow", "celery", "worker"], None, False),
        (["airflow", "triggerer"], None, False),
        (["airflow", "webserver"], "always", True),
        (["airflow", "dag-processor"], "never", False),
        (["python", "-c", "pass"], None, False),
    ],
)
def test_should_prewarm(prewarm_mod, argv, env, expected, monkeypatch):
    if env is None:
        monkeypatch.delenv("BIETLEJUICE_PREWARM", raising=False)
    else:
        monkeypatch.setenv("BIETLEJUICE_PREWARM", env)
    assert prewarm_mod._should_prewarm(argv) is expected


def test_prewarm_bietlejuice_never_raises(prewarm_mod):
    summary = prewarm_mod.prewarm_bietlejuice(modules=["json", "this_module_does_not_exist_xyz"])
    assert "json" in summary["imported"]
    assert any(n == "this_module_does_not_exist_xyz" for n, _ in summary["failed"])
    assert "elapsed_s" in summary
    assert "libyaml" in summary
    assert "plugin_count" in summary
    assert "line_folder_count" in summary
    assert summary["declarations"] == "disabled"
    assert summary["declaration_count"] == 0


def test_warm_airflow_plugins_reports_loaded_count(prewarm_mod):
    from airflow import plugins_manager

    with (
        mock.patch.object(plugins_manager, "ensure_plugins_loaded") as ensure,
        mock.patch.object(plugins_manager, "plugins", [object(), object()]),
    ):
        assert prewarm_mod._warm_airflow_plugins() == ("ok", 2)
    ensure.assert_called_once_with()


def test_warm_line_folders_reports_cached_count(prewarm_mod):
    get_folders = mock.Mock(return_value=[object()] * 3)
    fake_service = types.ModuleType(
        "bietlejuice.base.service.dag_packages_path_service"
    )
    fake_service.DAGPackagesPathService = type(
        "DAGPackagesPathService",
        (),
        {"_get_line_folders": get_folders},
    )
    with mock.patch.dict(
        sys.modules,
        {"bietlejuice.base.service.dag_packages_path_service": fake_service},
    ):
        assert prewarm_mod._warm_line_folders() == ("ok", 3)
    get_folders.assert_called_once_with()


def test_warm_dag_declarations_populates_parser_cache(
    prewarm_mod, monkeypatch, tmp_path
):
    declaration_path = tmp_path / "growth" / "example"
    declaration_path.mkdir(parents=True)
    (declaration_path / "example_declaration.yml").write_text("dag: {}")

    parse_declaration = mock.Mock(
        return_value={"workflow": {"layer": "clean"}}
    )
    parser_module = types.ModuleType("dag_yaml_parser")
    parser_module.DAGYamlParser = mock.Mock(
        side_effect=lambda _dag_name: types.SimpleNamespace(
            dag_declaration=parse_declaration
        )
    )

    line_folder = types.SimpleNamespace(path=str(tmp_path / "growth"))
    path_module = types.ModuleType("dag_packages_path_service")
    path_module.DAGPackagesPathService = type(
        "DAGPackagesPathService",
        (),
        {
            "_get_line_folders": mock.Mock(return_value=[line_folder]),
        },
    )

    monkeypatch.delenv("BIETLEJUICE_PREWARM_DECLARATIONS", raising=False)
    monkeypatch.setenv(
        "BIETLEJUICE_PREWARM_DECLARATIONS_TIMEOUT_S", "not-a-number"
    )
    with mock.patch.dict(
        sys.modules,
        {
            "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser": parser_module,
            "bietlejuice.base.service.dag_packages_path_service": path_module,
        },
    ):
        status, count, failures, _elapsed = prewarm_mod._warm_dag_declarations()

    assert (status, count, failures) == ("ok", 1, 0)
    parser_module.DAGYamlParser.assert_called_once_with("example")
    parse_declaration.assert_called_once_with()


@pytest.mark.parametrize("raw_timeout", ["", "not-a-number", "0", "-1", "inf"])
def test_invalid_declaration_timeout_falls_back_without_raising(
    prewarm_mod, monkeypatch, caplog, raw_timeout
):
    monkeypatch.setenv("BIETLEJUICE_PREWARM_DECLARATIONS_TIMEOUT_S", raw_timeout)

    with caplog.at_level("WARNING", logger="bietlejuice.prewarm"):
        timeout = prewarm_mod._declaration_prewarm_timeout(None)

    assert timeout == 120.0
    assert "using 120s" in caplog.text


def test_explicit_valid_declaration_timeout(prewarm_mod):
    assert prewarm_mod._declaration_prewarm_timeout(15) == 15.0


def test_install_fast_yaml_loader(prewarm_mod):
    status = prewarm_mod._install_fast_yaml_loader()
    import yaml

    if getattr(yaml, "__with_libyaml__", False):
        assert status == "installed"
        assert yaml.SafeLoader is yaml.CSafeLoader
        assert yaml.safe_load("a: 1") == {"a": 1}
    else:
        assert "unavailable" in status or "skipped" in status


def test_warm_configuration_service_warms_wonka_sentinel(prewarm_mod, monkeypatch):
    calls = []

    class FakeConfigService:
        def __init__(self, dag_name=None, intermediate_path=None):
            calls.append(dag_name)

        def get_config(self, key):
            return "bucket"

    fake_mod = types.ModuleType("bietlejuice.services.configuration_service")
    fake_mod.ConfigurationService = FakeConfigService
    fake_mod.WONKA_SHARED_CONFIG_DAG_NAME = "__wonka__"

    with mock.patch.dict(
        sys.modules,
        {"bietlejuice.services.configuration_service": fake_mod},
    ):
        assert prewarm_mod._warm_configuration_service() == "ok"

    assert None in calls
    assert "__wonka__" in calls
