"""Unit tests for services_integration_validations DAG (EMR job-cluster spine)."""

import inspect
import os
import sys
from unittest.mock import MagicMock

from airflow.models import BaseOperator
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

_BASE_OPERATOR_PARAMS = set(inspect.signature(BaseOperator.__init__).parameters)

_COMPUTE_CHAIN_TASK_IDS = frozenset(
    {
        "execute-job-cluster",
        "run-validations-suites",
        "terminate-emr-cluster",
    }
)


def _fake_emr_operator(*args, **kwargs):
    """Real BaseOperator stand-in for one emr_plugin operator."""
    known_kwargs = {
        key: value for key, value in kwargs.items() if key in _BASE_OPERATOR_PARAMS
    }
    return EmptyOperator(*args, **known_kwargs)


def _build_fake_emr_plugin():
    fake = MagicMock()
    fake.QuintoAndarEmrCreateClusterOperator = MagicMock(side_effect=_fake_emr_operator)
    fake.QuintoAndarEmrSubmitStepsOperator = MagicMock(side_effect=_fake_emr_operator)
    fake.QuintoAndarEmrTerminateClusterOperator = MagicMock(
        side_effect=_fake_emr_operator
    )
    fake.QuintoAndarEmrSubmitStepsOperator.build_spark_submit_step = MagicMock(
        return_value={
            "Name": "step",
            "ActionOnFailure": "CONTINUE",
            "HadoopJarStep": {},
        }
    )
    return fake


def _import_dag_module_with_fake_emr_plugin():
    """Import the DAG module with inert EMR operators (see vocs_machina_planning)."""
    os.environ.setdefault("ENVIRONMENT", "forno")
    original_emr_plugin = sys.modules.get("emr_plugin")
    sys.modules["emr_plugin"] = _build_fake_emr_plugin()
    try:
        import dags.platform.services_integration_validations.services_integration_validations as module
    finally:
        if original_emr_plugin is None:
            del sys.modules["emr_plugin"]
        else:
            sys.modules["emr_plugin"] = original_emr_plugin
    return module


_services_integration_validations = _import_dag_module_with_fake_emr_plugin()

CLUSTER_ARGS = _services_integration_validations.CLUSTER_ARGS
DAG_ID = _services_integration_validations.DAG_ID
dag = _services_integration_validations.dag


def _library_blob(custom_libraries):
    parts = []
    for lib in custom_libraries:
        if "pypi" in lib:
            parts.append(lib["pypi"]["package"])
        if "whl" in lib:
            parts.append(lib["whl"])
        if "jar" in lib:
            parts.append(lib["jar"])
        if "maven" in lib:
            parts.append(lib["maven"]["coordinates"])
    return "\n".join(parts)


class TestServicesIntegrationValidationsDag:
    def test_dag_id_and_schedule(self):
        # arrange / act / assert
        assert dag.dag_id == DAG_ID
        assert dag.dag_id == "bietlejuice.services_integration_validations"
        assert dag.schedule_interval == "0 13,16,18,20 * * *"

    def test_owner_is_data_life_cycle(self):
        # arrange / act
        owner = dag.default_args["owner"]
        # assert
        assert owner == DAGOwnerEnum.DATA_LIFE_CYCLE

    def test_compute_chain_task_ids_present(self):
        # arrange / act
        task_ids = set(dag.task_ids)
        # assert
        assert _COMPUTE_CHAIN_TASK_IDS <= task_ids

    def test_compute_chain_upstream_downstream(self):
        # arrange
        execute = dag.get_task("execute-job-cluster")
        run_task = dag.get_task("run-validations-suites")
        terminate = dag.get_task("terminate-emr-cluster")
        # act / assert
        assert execute.downstream_task_ids == {"run-validations-suites"}
        assert run_task.upstream_task_ids == {"execute-job-cluster"}
        assert run_task.downstream_task_ids == {"terminate-emr-cluster"}
        assert terminate.upstream_task_ids == {"run-validations-suites"}

    def test_no_databricks_operators_in_dag(self):
        # arrange / act
        operator_names = {task.__class__.__name__ for task in dag.tasks}
        # assert
        assert not any("Databricks" in name for name in operator_names)
        assert all(isinstance(task, EmptyOperator) for task in dag.tasks)

    def test_cluster_args_type_is_emr(self):
        # arrange / act
        cluster_type = CLUSTER_ARGS["type"]
        # assert
        assert cluster_type.startswith("emr_")

    def test_custom_libraries_include_required_artifacts(self):
        # arrange
        blob = _library_blob(CLUSTER_ARGS["custom_libraries"])
        # act / assert
        assert "hubspot-api-client==5.0.0" in blob
        assert "survicate-api-client-python" in blob
        assert "facebook-api-client-python" in blob
        assert "ojdbc8.jar" in blob

    def test_custom_libraries_exclude_dropped_artifacts(self):
        # arrange
        blob = _library_blob(CLUSTER_ARGS["custom_libraries"]).lower()
        # act / assert
        assert "validations-engine" not in blob
        assert "mysql-connector" not in blob
        assert "gsheets" not in blob

    def test_run_validations_suites_has_zero_retries(self):
        # arrange / act
        run_task = dag.get_task("run-validations-suites")
        # assert
        assert run_task.retries == 0
