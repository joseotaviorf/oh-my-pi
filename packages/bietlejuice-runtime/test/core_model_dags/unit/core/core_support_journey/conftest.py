"""Fixtures for core_support_journey DAG module tests."""

import importlib
import sys
from dataclasses import dataclass
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest


def _find_project_root() -> Path:
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    raise RuntimeError("Could not locate project root from test path")


PROJECT_ROOT = _find_project_root()
AIRFLOW_PKG_SRC = PROJECT_ROOT / "packages" / "bietlejuice-airflow" / "src"
DAG_MODULE_PATH = "dags.core.core_support_journey.core_support_journey"

_CONFIG_VALUES = {
    "databricks_bietlejuice_repo_path": "/test/bietlejuice",
    "datalake_bucket": "test-bucket",
    "cluster": {"type": "emr_7_12_small_general_2xlarge_single_node_cluster"},
    "dependencies": {
        "bietlejuice.salesforce": {
            "is_daily": True,
            "execution_hour": 6,
            "tasks": ["load-clean-record-types"],
        },
        "bietlejuice.salesforce_cdc": {
            "is_daily": False,
            "tasks": ["load_datalake_salesforce_clean_events_case"],
        },
    },
    "webhook_salesforce_cdc": "WEBHOOK_TEST",
}


def _ensure_import_paths() -> None:
    for path in (PROJECT_ROOT, AIRFLOW_PKG_SRC):
        path_str = str(path)
        if path_str not in sys.path:
            sys.path.insert(0, path_str)


@dataclass
class _DagExecutionContext:
    dag: object
    environment: str
    bucket: str
    base_spark_jobs_path: str
    dag_args: dict
    workflow_args: dict
    cluster_args: dict
    databricks_conn_id: str = "databricks_new"
    job_cluster_engine: object = None


def _install_dag_dependency_stubs(
    mock_engine: MagicMock, attach_engine_fn
) -> MagicMock:
    """Register lightweight stubs so the DAG module can import without Airflow."""

    class _DAG:
        def __init__(self, **kwargs):
            self.dag_id = kwargs.get("dag_id")

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    decorators = MagicMock()
    decorators.task_group = lambda **kwargs: lambda fn: fn

    baseoperator = MagicMock()
    baseoperator.BaseOperator = object

    models = MagicMock()
    models.baseoperator = baseoperator

    airflow_pkg = MagicMock()
    airflow_pkg.DAG = _DAG
    airflow_pkg.decorators = decorators
    airflow_pkg.models = models

    sys.modules["airflow"] = airflow_pkg
    sys.modules["airflow.decorators"] = decorators
    sys.modules["airflow.models"] = models
    sys.modules["airflow.models.baseoperator"] = baseoperator

    fake_jce = MagicMock()
    fake_jce.attach_job_cluster_engine_to_context = attach_engine_fn
    fake_jce.attach_emr_job_cluster_finished_work_prerequisites = MagicMock()
    fake_jce.get_job_cluster_completion_sink = MagicMock(
        return_value=Mock(task_id="cluster_completion_sink")
    )
    sys.modules["bietlejuice.base.airflow.job_cluster_engine"] = fake_jce

    fake_dec = MagicMock()
    fake_dec.DagExecutionContext = _DagExecutionContext
    sys.modules["bietlejuice.base.airflow.task_creators.dag_execution_context"] = (
        fake_dec
    )

    common_mod = importlib.import_module("bietlejuice.base.sst.airflow.common.common")
    sys.modules["bietlejuice.base.sst.airflow.common.common"] = common_mod

    fake_sst_base = MagicMock()
    fake_sst_base.SStPlaceholderOperator = MagicMock()
    sys.modules["bietlejuice.base.sst.airflow.operators.base"] = fake_sst_base

    fake_sst_sensors = MagicMock()
    fake_sst_sensors.SStExternalTaskSensor = MagicMock()
    sys.modules["bietlejuice.base.sst.airflow.operators.sensors"] = fake_sst_sensors

    fake_gchat = MagicMock()

    class _GchatCallback:
        def __init__(self, **kwargs):
            self.dag_failure_alert = MagicMock()

    fake_gchat.GchatCallback = _GchatCallback
    sys.modules["bietlejuice.base.notification.gchat_callback"] = fake_gchat

    return fake_jce


@pytest.fixture(scope="module")
def core_support_journey_module():
    """Import DAG module once with ConfigurationService and cluster engine mocked."""
    _ensure_import_paths()

    mock_engine = MagicMock()
    mock_engine.create_execute_cluster_task.return_value = Mock(
        task_id="execute_job_cluster"
    )
    mock_engine.create_spark_python_task.return_value = Mock(
        task_id="load_core_support_journey_cases"
    )

    def _attach_engine(ctx, _config_service):
        ctx.job_cluster_engine = mock_engine

    _install_dag_dependency_stubs(mock_engine, _attach_engine)

    with patch(
        "bietlejuice.services.configuration_service.ConfigurationService"
    ) as mock_config_service:
        mock_config_service.return_value.get_config.side_effect = lambda key, **kwargs: (
            _CONFIG_VALUES[key]
        )
        sys.modules.pop(DAG_MODULE_PATH, None)
        module = importlib.import_module(DAG_MODULE_PATH)
        module._mock_engine = mock_engine
        yield module
