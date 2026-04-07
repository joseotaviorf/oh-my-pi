from unittest.mock import MagicMock

import pytest
from airflow.models import DAG

from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.job_cluster_engine import (
    DatabricksJobClusterEngine,
    EmrJobClusterEngine,
    build_job_cluster_engine,
    get_job_cluster_completion_sink,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)


class TestResolveAirflowComputeMode:
    def test_emr_prefix_detected(self):
        from bietlejuice.base.airflow.cluster_config_resolver import (
            resolve_airflow_compute_mode,
        )

        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.side_effect = lambda key: {
            "emr_preset": {"spark_version": "emr-7-2"},
        }[key]
        use_emr, merged = resolve_airflow_compute_mode({"type": "emr_preset"}, config)
        assert use_emr is True
        assert merged["spark_version"] == "emr-7-2"

    def test_databricks_not_emr(self):
        from bietlejuice.base.airflow.cluster_config_resolver import (
            resolve_airflow_compute_mode,
        )

        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.side_effect = lambda key: {
            "dbr": {"spark_version": "16.4.x-scala2.12"},
        }[key]
        use_emr, _ = resolve_airflow_compute_mode({"type": "dbr"}, config)
        assert use_emr is False


class TestBuildJobClusterEngine:
    @pytest.fixture
    def base_ctx(self):
        dag = DAG(dag_id="t", schedule=None)
        return DagExecutionContext(
            dag=dag,
            environment="forno",
            bucket="b",
            base_spark_jobs_path="/x/spark_jobs/base/",
            dag_args={},
            workflow_args={},
            cluster_args={"type": "cluster_key"},
        )

    def test_returns_emr_engine_when_spark_version_emr_prefix(self, base_ctx):
        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.side_effect = lambda key: {
            "cluster_key": {"spark_version": "emr-7-0"},
        }[key]

        engine = build_job_cluster_engine(base_ctx, config)

        assert isinstance(engine, EmrJobClusterEngine)
        assert base_ctx.use_airflow_emr is True

    def test_returns_databricks_engine_otherwise(self, base_ctx):
        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.side_effect = lambda key: {
            "cluster_key": {
                "spark_version": "16.4.x-scala2.12",
                "data_security_mode": "NONE",
                "spark_env_vars": {},
            },
            "default_access_control_list": [
                {"group_name": "g", "permission_level": "CAN_MANAGE"}
            ],
            "default_libraries": [],
            "artifacts_bucket": "art",
            "databricks_default_service_credential_name": "x",
        }.get(key, {})

        engine = build_job_cluster_engine(base_ctx, config)

        assert isinstance(engine, DatabricksJobClusterEngine)
        assert base_ctx.use_airflow_emr is False


class TestDatabricksJobClusterEngineAcl:
    """ACL resolution moved from ExecuteJobClusterTaskCreator to DatabricksJobClusterEngine."""

    _DEFAULT_ACL = [
        {"group_name": "analytics-engineers", "permission_level": "CAN_MANAGE"}
    ]
    _MLOPS_ACL = {"group_name": "mlops", "permission_level": "CAN_MANAGE"}
    _CUSTOM_ACL = {"group_name": "people-analytics", "permission_level": "CAN_MANAGE"}

    @pytest.fixture
    def config_service(self):
        return MagicMock()

    def _engine(self, ctx, config_service):
        return DatabricksJobClusterEngine(ctx, config_service)

    def test_uses_acl_from_cluster_args_when_present_as_dict(self, config_service):
        ctx = MagicMock()
        ctx.cluster_args = {
            "type": "some_cluster",
            "access_control_list": self._CUSTOM_ACL,
        }
        engine = self._engine(ctx, config_service)
        result = engine._get_access_control_list()
        assert result == [self._CUSTOM_ACL]
        config_service.get_config.assert_not_called()

    def test_uses_acl_from_cluster_args_when_present_as_list(self, config_service):
        acl_list = [self._CUSTOM_ACL, self._MLOPS_ACL]
        ctx = MagicMock()
        ctx.cluster_args = {
            "type": "some_cluster",
            "access_control_list": acl_list,
        }
        engine = self._engine(ctx, config_service)
        result = engine._get_access_control_list()
        assert result == acl_list
        config_service.get_config.assert_not_called()

    def test_falls_back_to_cluster_template_acl_when_cluster_args_has_no_acl(
        self, config_service
    ):
        ctx = MagicMock()
        ctx.cluster_args = {"type": "wonka_cluster"}
        config_service.get_config.return_value = {
            "access_control_list": self._MLOPS_ACL
        }
        engine = self._engine(ctx, config_service)
        result = engine._get_access_control_list()
        assert result == [self._MLOPS_ACL]
        config_service.get_config.assert_called_once_with("wonka_cluster")

    def test_falls_back_to_cluster_template_acl_list_format(self, config_service):
        acl_list = [self._MLOPS_ACL, self._CUSTOM_ACL]
        ctx = MagicMock()
        ctx.cluster_args = {"type": "wonka_cluster"}
        config_service.get_config.return_value = {"access_control_list": acl_list}
        engine = self._engine(ctx, config_service)
        result = engine._get_access_control_list()
        assert result == acl_list
        config_service.get_config.assert_called_once_with("wonka_cluster")

    def test_falls_back_to_default_acl_when_template_has_no_acl(self, config_service):
        ctx = MagicMock()
        ctx.cluster_args = {"type": "databricks_16_4_med_general_cluster"}
        config_service.get_config.side_effect = lambda key: {
            "databricks_16_4_med_general_cluster": {},
            "default_access_control_list": self._DEFAULT_ACL,
        }[key]
        engine = self._engine(ctx, config_service)
        result = engine._get_access_control_list()
        assert result == [self._DEFAULT_ACL[0]]

    def test_falls_back_to_default_acl_when_cluster_type_is_none(self, config_service):
        ctx = MagicMock()
        ctx.cluster_args = {}
        config_service.get_config.return_value = self._DEFAULT_ACL
        engine = self._engine(ctx, config_service)
        result = engine._get_access_control_list()
        assert result == [self._DEFAULT_ACL[0]]
        config_service.get_config.assert_called_once_with("default_access_control_list")


class TestGetJobClusterCompletionSink:
    def test_returns_finished_when_engine_is_none(self):
        dag = DAG(dag_id="sink_none", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        ctx = MagicMock()
        ctx.job_cluster_engine = None

        sink = get_job_cluster_completion_sink(ctx, execute, finished, None)

        assert sink is finished

    def test_returns_finished_for_databricks_engine(self):
        dag = DAG(dag_id="sink_dbr", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        ctx = MagicMock()
        engine = MagicMock()
        engine.uses_emr_terminate_after_optimize = False
        ctx.job_cluster_engine = engine

        sink = get_job_cluster_completion_sink(ctx, execute, finished, None)

        assert sink is finished
        engine.create_emr_terminate_cluster_task.assert_not_called()

    def test_emr_creates_terminate_upstream_of_finished(self):
        dag = DAG(dag_id="sink_emr", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        terminate = EmptyOperator(task_id="terminate-emr-cluster", dag=dag)
        ctx = MagicMock()
        engine = MagicMock()
        engine.uses_emr_terminate_after_optimize = True
        engine.create_emr_terminate_cluster_task.return_value = terminate
        ctx.job_cluster_engine = engine

        sink = get_job_cluster_completion_sink(ctx, execute, finished, None)

        assert sink is terminate
        engine.create_emr_terminate_cluster_task.assert_called_once_with(
            execute_cluster_task_id="execute-job-cluster",
            terminate_task_local_suffix=None,
        )
        assert finished.upstream_task_ids == {"terminate-emr-cluster"}

    def test_emr_passes_suffix_when_local_id_gt_one(self):
        dag = DAG(dag_id="sink_emr2", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster-2", dag=dag)
        finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        terminate = EmptyOperator(task_id="terminate-emr-cluster-2", dag=dag)
        ctx = MagicMock()
        engine = MagicMock()
        engine.uses_emr_terminate_after_optimize = True
        engine.create_emr_terminate_cluster_task.return_value = terminate
        ctx.job_cluster_engine = engine

        sink = get_job_cluster_completion_sink(ctx, execute, finished, 2)

        assert sink is terminate
        engine.create_emr_terminate_cluster_task.assert_called_once_with(
            execute_cluster_task_id="execute-job-cluster-2",
            terminate_task_local_suffix=2,
        )
