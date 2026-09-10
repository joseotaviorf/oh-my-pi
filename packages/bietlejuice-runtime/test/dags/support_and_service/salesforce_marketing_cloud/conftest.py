"""Fixtures for the salesforce_marketing_cloud DAG module tests."""

import importlib
import sys
from dataclasses import dataclass
from pathlib import Path
from unittest.mock import MagicMock, patch

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
DAG_MODULE_PATH = (
    "dags.support_and_service.salesforce_marketing_cloud.salesforce_marketing_cloud"
)

OBJECTS_CONFIG = {
    "sonia_closing": {"external_identifier": "KEY-CLOSING"},
    "sonia_ep2ds_v2": {"external_identifier": "KEY-EP2DS"},
}
RAW_SCHEMA = "datalake_sfmc_raw"
CLEAN_SCHEMA = "datalake_sfmc_clean"
BUCKET = "test-bucket"
REPO_PATH = "/test/bietlejuice"

_CONFIG_VALUES = {
    "databricks_bietlejuice_repo_path": REPO_PATH,
    "datalake_bucket": BUCKET,
    "raw_schema": RAW_SCHEMA,
    "clean_schema": CLEAN_SCHEMA,
    "objects_config": OBJECTS_CONFIG,
    "cluster": {"type": "emr_7_12_consolidation_xs_general_single_node_cluster"},
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


def _install_dag_dependency_stubs(attach_engine_fn) -> None:
    """Register lightweight stubs so the DAG module can import without Airflow."""

    class _DAG:
        def __init__(self, **kwargs):
            self.dag_id = kwargs.get("dag_id")

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    airflow_pkg = MagicMock()
    airflow_pkg.DAG = _DAG
    sys.modules["airflow"] = airflow_pkg

    fake_jce = MagicMock()
    fake_jce.attach_job_cluster_engine_to_context = attach_engine_fn
    fake_jce.attach_emr_job_cluster_finished_work_prerequisites = MagicMock()
    fake_jce.attach_emr_terminate_cluster_work_prerequisites = MagicMock()
    fake_jce.get_job_cluster_completion_sink = MagicMock(
        return_value=MagicMock(task_id="terminate-emr-cluster")
    )
    sys.modules["bietlejuice.base.airflow.job_cluster_engine"] = fake_jce

    fake_dec = MagicMock()
    fake_dec.DagExecutionContext = _DagExecutionContext
    sys.modules["bietlejuice.base.airflow.task_creators.dag_execution_context"] = (
        fake_dec
    )

    fake_dataset_adder = MagicMock()
    fake_dataset_adder.DatasetAdder = MagicMock()
    sys.modules["bietlejuice.base.airflow.datasets.dataset_adder"] = fake_dataset_adder

    common_mod = importlib.import_module("bietlejuice.base.sst.airflow.common.common")
    sys.modules["bietlejuice.base.sst.airflow.common.common"] = common_mod

    fake_sst_base = MagicMock()
    fake_sst_base.SStPlaceholderOperator = MagicMock()
    sys.modules["bietlejuice.base.sst.airflow.operators.base"] = fake_sst_base

    fake_gchat = MagicMock()

    class _GchatCallback:
        def __init__(self, **kwargs):
            self.webhook_url_variable = kwargs.get("webhook_url_variable")
            self.dag_failure_alert = MagicMock()
            self.task_failure_alert = MagicMock()

    fake_gchat.GchatCallback = _GchatCallback
    sys.modules["bietlejuice.base.notification.gchat_callback"] = fake_gchat


@pytest.fixture(scope="module")
def dag_module():
    """Import the DAG module once with the config service and cluster engine mocked."""
    _ensure_import_paths()

    mock_engine = MagicMock()
    mock_engine.create_execute_cluster_task.return_value = MagicMock(
        task_id="execute-job-cluster"
    )
    mock_engine.create_spark_python_task.side_effect = lambda **kwargs: MagicMock(
        task_id=kwargs["task_id"]
    )

    def _attach_engine(ctx, _config_service):
        ctx.job_cluster_engine = mock_engine

    _install_dag_dependency_stubs(_attach_engine)

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


@pytest.fixture(scope="module")
def spark_task_calls(dag_module):
    """Every create_spark_python_task call the DAG made at import time."""
    return dag_module._mock_engine.create_spark_python_task.call_args_list


@pytest.fixture(scope="module")
def config():
    """The config values the DAG module was imported with."""
    return _CONFIG_VALUES
