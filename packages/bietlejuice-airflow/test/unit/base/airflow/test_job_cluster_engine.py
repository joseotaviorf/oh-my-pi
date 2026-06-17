import sys
from datetime import timedelta
from unittest.mock import MagicMock, patch

import pytest
from airflow.models import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.job_cluster_engine import (
    DatabricksJobClusterEngine,
    EmrJobClusterEngine,
    attach_emr_job_cluster_finished_work_prerequisites,
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


class TestEmrJobClusterEngineRetries:
    _MERGED = {"spark_version": "emr-7-0"}

    @staticmethod
    def _install_fake_emr_plugin(create_cls=None, submit_cls=None, terminate_cls=None):
        fake = MagicMock()
        fake.QuintoAndarEmrCreateClusterOperator = create_cls or MagicMock()
        submit_op = submit_cls or MagicMock()
        fake.QuintoAndarEmrSubmitStepsOperator = submit_op
        fake.QuintoAndarEmrTerminateClusterOperator = terminate_cls or MagicMock()
        submit_op.build_spark_submit_step = MagicMock(
            return_value={
                "Name": "x",
                "ActionOnFailure": "CONTINUE",
                "HadoopJarStep": {"Jar": "command-runner.jar", "Args": []},
            }
        )
        patcher = patch.dict(sys.modules, {"emr_plugin": fake})
        return fake, patcher

    @pytest.fixture
    def emr_ctx(self):
        dag = DAG(dag_id="emr_retries", schedule=None)
        ctx = DagExecutionContext(
            dag=dag,
            environment="forno",
            bucket="b",
            base_spark_jobs_path="/x/",
            dag_args={},
            workflow_args={},
            cluster_args={"type": "emr_cluster"},
        )
        ctx.aws_conn_id = "aws_default"
        return ctx

    def test_create_cluster_defaults_retries_three(self, emr_ctx):
        mock_create = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(create_cls=mock_create)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        with patcher:
            engine.create_execute_cluster_task(
                config_service=MagicMock(),
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
        kwargs = mock_create.call_args.kwargs
        assert kwargs["retries"] == 3
        assert "retry_delay" not in kwargs
        assert kwargs["deferrable"] is True
        assert (
            "airflow_emr_create_cluster_deferrable"
            not in kwargs["cluster_configuration"]
        )

    def test_create_cluster_airflow_emr_create_cluster_deferrable_false(self, emr_ctx):
        mock_create = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(create_cls=mock_create)
        merged = {**self._MERGED, "airflow_emr_create_cluster_deferrable": False}
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        with patcher:
            engine.create_execute_cluster_task(
                config_service=MagicMock(),
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
        kwargs = mock_create.call_args.kwargs
        assert kwargs["deferrable"] is False
        assert (
            "airflow_emr_create_cluster_deferrable"
            not in kwargs["cluster_configuration"]
        )

    def test_create_cluster_override_retries_and_delay(self, emr_ctx):
        emr_ctx.cluster_args["emr_task_retries"] = 7
        emr_ctx.cluster_args["emr_retry_delay_seconds"] = 90
        mock_create = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(create_cls=mock_create)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        with patcher:
            engine.create_execute_cluster_task(
                config_service=MagicMock(),
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
        kwargs = mock_create.call_args.kwargs
        assert kwargs["retries"] == 7
        assert kwargs["retry_delay"] == timedelta(seconds=90)

    def test_submit_steps_matches_retry_kwargs(self, emr_ctx):
        emr_ctx.cluster_args["emr_task_retries"] = 1
        mock_create = MagicMock()
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(
            create_cls=mock_create, submit_cls=mock_submit
        )
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        with patcher:
            engine.create_execute_cluster_task(
                config_service=MagicMock(),
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        kwargs = mock_submit.call_args.kwargs
        assert kwargs["retries"] == 1

    def test_submit_steps_includes_s3a_bucket_owner_full_control_acl(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        step_kwargs = mock_submit.build_spark_submit_step.call_args.kwargs
        extra = step_kwargs["extra_spark_args"]
        flat = " ".join(extra)
        assert "spark.hadoop.fs.s3a.acl.default=BucketOwnerFullControl" in flat
        assert "spark.hadoop.fs.s3a.canned.acl=BucketOwnerFullControl" in flat

    def test_submit_steps_uses_client_deploy_mode_by_default(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        step_kwargs = mock_submit.build_spark_submit_step.call_args.kwargs
        assert step_kwargs["deploy_mode"] == "client"

    def test_submit_steps_honors_emr_deploy_mode_override(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        merged = {**self._MERGED, "emr_deploy_mode": "cluster"}
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        step_kwargs = mock_submit.build_spark_submit_step.call_args.kwargs
        assert step_kwargs["deploy_mode"] == "cluster"

    def test_submit_steps_does_not_set_interpreter_by_default(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="optimize-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        flat = " ".join(
            mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        )
        assert "spark.pyspark.python" not in flat
        assert "spark.pyspark.driver.python" not in flat

    def test_submit_steps_python_interpreter_path_injects_confs(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-wonka-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
                python_interpreter_path="/home/hadoop/venv/bin/python",
            )
        flat = " ".join(
            mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        )
        assert "spark.pyspark.python=/home/hadoop/venv/bin/python" in flat
        assert "spark.pyspark.driver.python=/home/hadoop/venv/bin/python" in flat

    def test_submit_steps_empty_python_interpreter_path_is_noop(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-wonka-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
                python_interpreter_path="",
            )
        flat = " ".join(
            mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        )
        assert "spark.pyspark.python" not in flat

    def test_terminate_matches_retry_kwargs(self, emr_ctx):
        emr_ctx.cluster_args["emr_retry_delay_seconds"] = 45
        mock_term = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(terminate_cls=mock_term)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        with patcher:
            engine.create_emr_terminate_cluster_task(
                execute_cluster_task_id="execute-job-cluster",
                terminate_task_local_suffix=None,
            )
        kwargs = mock_term.call_args.kwargs
        assert kwargs["retries"] == 3
        assert kwargs["retry_delay"] == timedelta(seconds=45)

    def test_validation_emr_operators_use_zero_retries(self, emr_ctx):
        emr_ctx.is_validation = True
        emr_ctx.cluster_args["emr_task_retries"] = 7
        emr_ctx.cluster_args["emr_retry_delay_seconds"] = 90
        mock_create = MagicMock()
        mock_submit = MagicMock()
        mock_term = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(
            create_cls=mock_create,
            submit_cls=mock_submit,
            terminate_cls=mock_term,
        )
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        with patcher:
            engine.create_execute_cluster_task(
                config_service=MagicMock(),
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
            engine.create_emr_terminate_cluster_task(
                execute_cluster_task_id="execute-job-cluster",
                terminate_task_local_suffix=None,
            )
        for operator_mock in (mock_create, mock_submit, mock_term):
            kwargs = operator_mock.call_args.kwargs
            assert kwargs["retries"] == 0
            assert "retry_delay" not in kwargs


class TestValidationEventLogOverrides:
    _CLUSTER_TEMPLATE = {
        "spark_version": "16.4.x-scala2.12",
        "data_security_mode": "SINGLE_USER",
        "spark_conf": {
            "spark.eventLog.enabled": "true",
            "spark.eventLog.dir": "s3a://bucket/spark-event-logs/dag",
        },
        "spark_env_vars": {},
    }

    @pytest.fixture
    def dbr_ctx(self):
        dag = DAG(dag_id="bietlejuice.foo__validation", schedule=None)
        return DagExecutionContext(
            dag=dag,
            environment="forno",
            bucket="b",
            base_spark_jobs_path="/x/",
            dag_args={},
            workflow_args={},
            cluster_args={"type": "cluster_key"},
            is_validation=True,
        )

    def test_databricks_validation_disables_event_log(self, dbr_ctx):
        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.side_effect = lambda key: {
            "cluster_key": dict(self._CLUSTER_TEMPLATE),
            "default_libraries": [],
            "artifacts_bucket": "art",
            "databricks_default_service_credential_name": "x",
            "default_access_control_list": [
                {"group_name": "g", "permission_level": "CAN_MANAGE"}
            ],
        }.get(key, [])

        mock_operator = MagicMock()
        with patch(
            "bietlejuice.base.airflow.job_cluster_engine."
            "QuintoAndarDatabricksExecuteJobClusterOperator",
            mock_operator,
        ):
            engine = DatabricksJobClusterEngine(dbr_ctx, config)
            engine.create_execute_cluster_task(
                config_service=config,
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )

        cluster_configuration = mock_operator.call_args.kwargs["cluster_configuration"]
        assert cluster_configuration["spark_conf"]["spark.eventLog.enabled"] == "false"

    def test_emr_validation_disables_event_log_via_build_engine(self):
        dag = DAG(dag_id="bietlejuice.foo__validation", schedule=None)
        ctx = DagExecutionContext(
            dag=dag,
            environment="forno",
            bucket="b",
            base_spark_jobs_path="/x/",
            dag_args={},
            workflow_args={},
            cluster_args={"type": "emr_cluster"},
            is_validation=True,
        )
        merged = {
            "spark_version": "emr-7-0",
            "spark_conf": {
                "spark.eventLog.enabled": "true",
                "spark.eventLog.dir": "s3a://bucket/spark-event-logs-emr/dag",
            },
        }
        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.return_value = merged

        with patch(
            "bietlejuice.base.airflow.job_cluster_engine.resolve_airflow_compute_mode",
            return_value=(True, dict(merged)),
        ):
            engine = build_job_cluster_engine(ctx, config)

        assert isinstance(engine, EmrJobClusterEngine)
        assert (
            engine._merged_cluster_configuration["spark_conf"]["spark.eventLog.enabled"]
            == "false"
        )


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


class TestAttachEmrJobClusterFinishedPrerequisites:
    def test_noop_when_not_emr(self):
        dag = DAG(dag_id="a_emr_off", schedule=None)
        work = EmptyOperator(task_id="work", dag=dag)
        jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        term = EmptyOperator(task_id="terminate", dag=dag)
        work.set_downstream(term)
        ctx = MagicMock()
        ctx.use_airflow_emr = False

        attach_emr_job_cluster_finished_work_prerequisites(
            ctx,
            jcf,
            (work,),
        )

        assert not jcf.upstream_task_ids

    def test_emr_adds_explicit_upstreams(self):
        dag = DAG(dag_id="a_emr_explicit", schedule=None)
        w1 = EmptyOperator(task_id="w1", dag=dag)
        w2 = EmptyOperator(task_id="w2", dag=dag)
        jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        ctx = MagicMock()
        ctx.use_airflow_emr = True

        attach_emr_job_cluster_finished_work_prerequisites(ctx, jcf, (w1, w2))

        assert jcf.upstream_task_ids == {"w1", "w2"}

    def test_emr_uses_cluster_completion_sink_upstream(self):
        dag = DAG(dag_id="a_emr_sink", schedule=None)
        work = EmptyOperator(task_id="work", dag=dag)
        term = EmptyOperator(task_id="terminate-emr-cluster", dag=dag)
        jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        work.set_downstream(term)
        term.set_downstream(jcf)
        ctx = MagicMock()
        ctx.use_airflow_emr = True

        attach_emr_job_cluster_finished_work_prerequisites(
            ctx, jcf, cluster_completion_sink=term
        )

        assert jcf.upstream_task_ids == {"work", "terminate-emr-cluster"}

    def test_raises_if_both_explicit_and_sink(self):
        dag = DAG(dag_id="a_bad", schedule=None)
        a = EmptyOperator(task_id="a", dag=dag)
        b = EmptyOperator(task_id="b", dag=dag)
        jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        ctx = MagicMock()
        ctx.use_airflow_emr = True

        with pytest.raises(
            ValueError,
            match="at most one of work_completion_tasks or cluster_completion_sink",
        ):
            attach_emr_job_cluster_finished_work_prerequisites(
                ctx, jcf, (a,), cluster_completion_sink=b
            )
