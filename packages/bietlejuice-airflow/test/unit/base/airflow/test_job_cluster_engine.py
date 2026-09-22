import sys
from datetime import timedelta
from unittest.mock import MagicMock, patch

import pytest
from airflow.models import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.job_cluster_engine import (
    METADATA_TASK_LIGHTWEIGHT_SPARK_CONF,
    DatabricksJobClusterEngine,
    DatabricksTaskSubmissionEngine,
    EmrJobClusterEngine,
    attach_emr_job_cluster_finished_work_prerequisites,
    attach_emr_terminate_cluster_work_prerequisites,
    build_job_cluster_engine,
    collect_emr_cluster_work_tasks,
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

    def test_emr_type_wins_over_leftover_databricks_spark_version(self):
        """Regression: promoted EMR clusters with leftover DBR spark_version.

        Leftover ``spark_version: 13.3.x-scala2.12`` must not route ``emr_*``
        presets through DatabricksJobClusterEngine (KeyError data_security_mode).
        """
        from bietlejuice.base.airflow.cluster_config_resolver import (
            resolve_airflow_compute_mode,
        )

        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.side_effect = lambda key: {
            "emr_7_12_consolidation_s_general_single_node_fleet_cluster": {
                "spark_version": "emr-7.12.0",
            },
        }[key]
        use_emr, merged = resolve_airflow_compute_mode(
            {
                "type": "emr_7_12_consolidation_s_general_single_node_fleet_cluster",
                "custom_configurations": {"spark_version": "13.3.x-scala2.12"},
            },
            config,
        )
        assert use_emr is True
        assert merged["spark_version"] == "13.3.x-scala2.12"


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

    def test_returns_task_submission_engine_when_mode_set(self, base_ctx):
        base_ctx.databricks_submission_mode = "task_submission"
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

        assert isinstance(engine, DatabricksTaskSubmissionEngine)
        assert base_ctx.use_airflow_emr is False


class TestDatabricksTaskSubmissionEngine:
    @pytest.fixture
    def databricks_ctx(self):
        dag = DAG(dag_id="gsheets_test", schedule=None)
        return DagExecutionContext(
            dag=dag,
            environment="forno",
            bucket="b",
            base_spark_jobs_path="/repo/spark_jobs/base/",
            dag_args={},
            workflow_args={},
            cluster_args={
                "type": "consolidation_s_memory_cluster",
                "databricks_conn_id": "databricks_new",
            },
            databricks_submission_mode="task_submission",
        )

    def test_create_execute_cluster_uses_create_cluster_task_id(self, databricks_ctx):
        config = MagicMock()
        config._deep_update = lambda a, b: {**a, **(b or {})}
        config.get_config.side_effect = lambda key: {
            "consolidation_s_memory_cluster": {
                "spark_version": "16.4.x-scala2.12",
                "data_security_mode": "SINGLE_USER",
                "spark_env_vars": {},
            },
            "default_access_control_list": [
                {"group_name": "g", "permission_level": "CAN_MANAGE"}
            ],
            "default_libraries": [],
            "artifacts_bucket": "art",
            "databricks_default_service_credential_name": "x",
        }.get(key, [])
        with patch(
            "bietlejuice.base.airflow.job_cluster_engine.QuintoAndarDatabricksCreateClusterOperator"
        ) as mock_create:
            engine = DatabricksTaskSubmissionEngine(databricks_ctx, config)
            engine.create_execute_cluster_task(
                config_service=config,
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
            mock_create.assert_called_once()
            assert mock_create.call_args.kwargs["task_id"] == "create-cluster"

    def test_create_spark_python_task_uses_submit_run(self, databricks_ctx):
        config = MagicMock()
        with patch(
            "bietlejuice.base.airflow.job_cluster_engine.QuintoAndarDatabricksSubmitRunOperator"
        ) as mock_submit:
            engine = DatabricksTaskSubmissionEngine(databricks_ctx, config)
            engine.create_spark_python_task(
                spark_job_path="/repo/spark_jobs/base/job.py",
                task_id="load-gsheets-t",
                job_parameters=["forno", "bucket"],
                execution_timeout_hours=2,
                pool="gsheets_pool",
                do_output_xcom_push=True,
            )
            mock_submit.assert_called_once()
            kwargs = mock_submit.call_args.kwargs
            assert kwargs["do_output_xcom_push"] is True
            assert kwargs["pool"] == "gsheets_pool"

    def test_create_databricks_terminate_cluster_task(self, databricks_ctx):
        config = MagicMock()
        with patch(
            "bietlejuice.base.airflow.job_cluster_engine.QuintoAndarDatabricksTerminateClusterOperator"
        ) as mock_terminate:
            engine = DatabricksTaskSubmissionEngine(databricks_ctx, config)
            engine.create_databricks_terminate_cluster_task()
            mock_terminate.assert_called_once()
            assert mock_terminate.call_args.kwargs["task_id"] == "terminate-cluster"


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

    def test_create_cluster_injects_inmetro_from_yarn_env_spark_version(self, emr_ctx):
        mock_create = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(create_cls=mock_create)
        merged = {
            "spark_version": "emr-7-0",
            "emr_configurations": [
                {
                    "Classification": "yarn-env",
                    "Configurations": [
                        {
                            "Classification": "export",
                            "Properties": {"SPARK_VERSION": "3.5"},
                        }
                    ],
                    "Properties": {},
                }
            ],
        }
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        with patcher:
            engine.create_execute_cluster_task(
                config_service=MagicMock(),
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
        props = mock_create.call_args.kwargs["cluster_configuration"][
            "emr_configurations"
        ][0]["Configurations"][0]["Properties"]
        assert props["INMETRO_VERSION"] == "4.11.0"
        assert props["DEEQU_JAR_VERSION"] == "2.0.8"

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

    def test_create_cluster_airflow_emr_create_cluster_deferrable_true(self, emr_ctx):
        mock_create = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(create_cls=mock_create)
        merged = {**self._MERGED, "airflow_emr_create_cluster_deferrable": True}
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        with patcher:
            engine.create_execute_cluster_task(
                config_service=MagicMock(),
                minimum_cluster_runtime_version=None,
                execute_job_cluster_local_id=None,
            )
        kwargs = mock_create.call_args.kwargs
        assert kwargs["deferrable"] is True
        assert (
            "airflow_emr_create_cluster_deferrable"
            not in kwargs["cluster_configuration"]
        )

    def test_create_cluster_airflow_emr_create_cluster_deferrable_false_passes_false(
        self, emr_ctx
    ):
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
        assert kwargs["deferrable"] is True

    def test_submit_steps_deferrable_true_when_config_overrides(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        merged = {**self._MERGED, "airflow_emr_create_cluster_deferrable": True}
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        assert mock_submit.call_args.kwargs["deferrable"] is True

    def test_submit_steps_merges_cluster_spark_sql_extensions(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        merged = {
            **self._MERGED,
            "spark_conf": {
                "spark.sql.extensions": (
                    "org.apache.sedona.viz.sql.SedonaVizExtensions,"
                    "org.apache.sedona.sql.SedonaSqlExtensions"
                ),
                "spark.kryo.registrator": "org.apache.sedona.core.serde.SedonaKryoRegistrator",
                "spark.serializer": "org.apache.spark.serializer.KryoSerializer",
            },
        }
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-polygon_region",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        flat = " ".join(
            mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        )
        assert (
            "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension,"
            "org.apache.sedona.viz.sql.SedonaVizExtensions,"
            "org.apache.sedona.sql.SedonaSqlExtensions"
        ) in flat
        assert (
            "spark.kryo.registrator=org.apache.sedona.core.serde.SedonaKryoRegistrator"
            in flat
        )
        assert "spark.serializer=org.apache.spark.serializer.KryoSerializer" in flat

    def test_submit_steps_does_not_inject_kryo_without_explicit_spark_conf(
        self, emr_ctx
    ):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        merged = {
            **self._MERGED,
            "spark_conf": {
                "spark.serializer": "org.apache.spark.serializer.KryoSerializer",
                "spark.sql.extensions": (
                    "org.apache.sedona.viz.sql.SedonaVizExtensions,"
                    "org.apache.sedona.sql.SedonaSqlExtensions"
                ),
            },
        }
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-polygon_region",
                job_parameters=["a"],
                execution_timeout_hours=2,
            )
        flat = " ".join(
            mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        )
        assert (
            "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension,"
            "org.apache.sedona.viz.sql.SedonaVizExtensions,"
            "org.apache.sedona.sql.SedonaSqlExtensions"
        ) in flat
        assert "spark.kryo.registrator" not in flat

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

    def test_submit_steps_encodes_empty_job_parameters_as_none_literal(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="load-foo",
                job_parameters=["forno", "", None, "my_tree"],
                execution_timeout_hours=2,
            )
        step_kwargs = mock_submit.build_spark_submit_step.call_args.kwargs
        assert step_kwargs["args"] == ["forno", "None", "None", "my_tree"]

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

    def test_submit_steps_task_spark_conf_none_is_noop(self, emr_ctx):
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
                task_spark_conf=None,
            )
        extra = mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        # Only baseline args (Delta + S3A ACL + runtime env + OpenLineage).
        assert not any("spark.driver.memory" in a for a in extra)
        assert not any("spark.executor.memory" in a for a in extra)

    def test_submit_steps_task_spark_conf_injects_all_keys(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        conf = {
            "spark.driver.memory": "1g",
            "spark.executor.cores": "1",
            "spark.dynamicAllocation.maxExecutors": "1",
        }
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="sync-metadata-clean-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
                task_spark_conf=conf,
            )
        flat = " ".join(
            mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        )
        assert "spark.driver.memory=1g" in flat
        assert "spark.executor.cores=1" in flat
        assert "spark.dynamicAllocation.maxExecutors=1" in flat

    def test_submit_steps_task_spark_conf_appended_after_openlineage(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="optimize-clean-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
                task_spark_conf={"spark.executor.cores": "4"},
            )
        extra = mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        # Concatenate ["--conf", "key=value", ...] pairs and locate positions of key markers.
        pairs = [
            f"{extra[i]} {extra[i + 1]}"
            for i in range(0, len(extra), 2)
            if extra[i] == "--conf"
        ]
        openlineage_index = next(
            i for i, p in enumerate(pairs) if "spark.openlineage.parentJobName" in p
        )
        task_conf_index = next(
            i for i, p in enumerate(pairs) if "spark.executor.cores=4" in p
        )
        assert task_conf_index > openlineage_index, (
            "task_spark_conf must be appended AFTER OpenLineage so spark-submit "
            "keeps its value when a duplicate key is provided by cluster defaults."
        )

    def test_submit_steps_metadata_lightweight_profile_shape(self, emr_ctx):
        mock_submit = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(submit_cls=mock_submit)
        engine = EmrJobClusterEngine(emr_ctx, self._MERGED, MagicMock())
        emr_ctx.emr_active_create_cluster_task_id = "execute-job-cluster"
        with patcher:
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="register-table-clean-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
                task_spark_conf=METADATA_TASK_LIGHTWEIGHT_SPARK_CONF,
            )
        flat = " ".join(
            mock_submit.build_spark_submit_step.call_args.kwargs["extra_spark_args"]
        )
        assert "spark.driver.memory=1g" in flat
        assert "spark.executor.memory=1g" in flat
        assert "spark.executor.cores=1" in flat
        assert "spark.dynamicAllocation.maxExecutors=1" in flat

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
        assert kwargs["deferrable"] is True

    def test_terminate_deferrable_true_when_config_overrides(self, emr_ctx):
        mock_term = MagicMock()
        fake, patcher = self._install_fake_emr_plugin(terminate_cls=mock_term)
        merged = {**self._MERGED, "airflow_emr_create_cluster_deferrable": True}
        engine = EmrJobClusterEngine(emr_ctx, merged, MagicMock())
        with patcher:
            engine.create_emr_terminate_cluster_task(
                execute_cluster_task_id="execute-job-cluster",
                terminate_task_local_suffix=None,
            )
        assert mock_term.call_args.kwargs["deferrable"] is True

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


class TestDatabricksJobClusterEngineTaskSparkConf:
    """task_spark_conf is EMR-only; Databricks must accept it without side effects."""

    def test_databricks_ignores_task_spark_conf_without_error(self):
        dag = DAG(dag_id="dbr_task_spark_conf", schedule=None)
        ctx = DagExecutionContext(
            dag=dag,
            environment="forno",
            bucket="b",
            base_spark_jobs_path="/x/",
            dag_args={},
            workflow_args={},
            cluster_args={"type": "cluster_key"},
        )
        ctx.databricks_conn_id = "databricks_default"

        mock_operator = MagicMock()
        with patch(
            "bietlejuice.base.airflow.job_cluster_engine."
            "QuintoAndarDatabricksCheckJobTaskOperator",
            mock_operator,
        ):
            engine = DatabricksJobClusterEngine(ctx, MagicMock())
            engine.create_spark_python_task(
                spark_job_path="s3://b/j.py",
                task_id="register-table-clean-foo",
                job_parameters=["a"],
                execution_timeout_hours=2,
                task_spark_conf=METADATA_TASK_LIGHTWEIGHT_SPARK_CONF,
            )

        json_arg = mock_operator.call_args.kwargs["json"]
        # Databricks CheckJob JSON payload has no room for per-task Spark resource
        # overrides; the profile must be silently dropped.
        assert "spark_python_task" in json_arg
        assert "spark_conf" not in json_arg
        assert "new_cluster" not in json_arg


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
        assert not finished.upstream_task_ids

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
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        execute >> work >> term
        ctx = MagicMock()
        ctx.use_airflow_emr = True

        attach_emr_job_cluster_finished_work_prerequisites(
            ctx, jcf, cluster_completion_sink=term
        )
        assert not jcf.upstream_task_ids

        attach_emr_terminate_cluster_work_prerequisites(
            ctx, term, execute_job_cluster_task=execute
        )

        assert jcf.upstream_task_ids == {"work", "terminate-emr-cluster"}
        assert term.upstream_task_ids == {"work"}

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


class TestCollectEmrClusterWorkTasks:
    def test_collect_emr_cluster_work_tasks(self):
        dag = DAG(dag_id="collect_work", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        load = EmptyOperator(task_id="load", dag=dag)
        register = EmptyOperator(task_id="register", dag=dag)
        sync = EmptyOperator(task_id="sync", dag=dag)
        data_quality = EmptyOperator(task_id="data_quality", dag=dag)
        optimize = EmptyOperator(task_id="optimize", dag=dag)
        term = EmptyOperator(task_id="terminate-emr-cluster", dag=dag)

        execute >> load >> register >> sync >> optimize >> term
        load >> data_quality >> optimize

        collected = collect_emr_cluster_work_tasks(execute, term)

        assert {task.task_id for task in collected} == {
            "load",
            "register",
            "sync",
            "data_quality",
            "optimize",
        }

    def test_collect_skips_sink_and_does_not_traverse_past_terminate(self):
        dag = DAG(dag_id="collect_sink", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        load = EmptyOperator(task_id="load", dag=dag)
        term = EmptyOperator(task_id="terminate-emr-cluster", dag=dag)
        finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)

        execute >> load >> term >> finished

        collected = collect_emr_cluster_work_tasks(execute, term)

        assert [task.task_id for task in collected] == ["load"]
        assert "job-cluster-finished" not in {task.task_id for task in collected}

    def test_collector_never_includes_job_cluster_finished_parallel_path(self):
        dag = DAG(dag_id="collect_jcf_parallel", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        load = EmptyOperator(task_id="load", dag=dag)
        term = EmptyOperator(task_id="terminate-emr-cluster", dag=dag)
        finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)

        execute >> load >> term >> finished
        load >> finished

        collected = collect_emr_cluster_work_tasks(execute, term)

        assert [task.task_id for task in collected] == ["load"]
        assert "job-cluster-finished" not in {task.task_id for task in collected}


class TestAttachEmrTerminateClusterWorkPrerequisites:
    def test_noop_when_not_emr(self):
        dag = DAG(dag_id="term_noop_off", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        w1 = EmptyOperator(task_id="w1", dag=dag)
        optimize = EmptyOperator(task_id="optimize", dag=dag)
        term = EmptyOperator(task_id="terminate-emr-cluster", dag=dag)
        execute >> w1 >> optimize >> term
        ctx = MagicMock()
        ctx.use_airflow_emr = False

        attach_emr_terminate_cluster_work_prerequisites(
            ctx, term, execute_job_cluster_task=execute
        )

        assert term.upstream_task_ids == {"optimize"}

    def test_emr_wires_all_collected_work_tasks_as_upstreams(self):
        dag = DAG(dag_id="term_work_up", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        w1 = EmptyOperator(task_id="w1", dag=dag)
        w2 = EmptyOperator(task_id="w2", dag=dag)
        optimize = EmptyOperator(task_id="optimize", dag=dag)
        term = EmptyOperator(
            task_id="terminate-emr-cluster",
            dag=dag,
            trigger_rule="all_done",
        )
        EmptyOperator(task_id="job-cluster-finished", dag=dag)
        execute >> w1 >> optimize
        execute >> w2 >> optimize
        optimize >> term
        ctx = MagicMock()
        ctx.use_airflow_emr = True

        attach_emr_terminate_cluster_work_prerequisites(
            ctx, term, execute_job_cluster_task=execute
        )

        assert term.upstream_task_ids == {"w1", "w2", "optimize"}

    def test_emr_register_retry_race_regression(self):
        """Register must be a direct upstream while sync/optimize are only via edges."""
        dag = DAG(dag_id="term_retry_race", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        load = EmptyOperator(task_id="load", dag=dag)
        register = EmptyOperator(task_id="register", dag=dag)
        sync = EmptyOperator(task_id="sync", dag=dag)
        optimize = EmptyOperator(
            task_id="optimize", dag=dag, trigger_rule="all_success"
        )
        term = EmptyOperator(
            task_id="terminate-emr-cluster",
            dag=dag,
            trigger_rule="all_done",
        )
        EmptyOperator(task_id="job-cluster-finished", dag=dag)
        execute >> load >> register >> sync >> optimize >> term
        ctx = MagicMock()
        ctx.use_airflow_emr = True

        attach_emr_terminate_cluster_work_prerequisites(
            ctx, term, execute_job_cluster_task=execute
        )

        assert "register" in term.upstream_task_ids
        assert term.upstream_task_ids >= {"load", "register", "sync", "optimize"}
        finished = dag.get_task("job-cluster-finished")
        assert finished.upstream_task_ids >= {"load", "register", "sync", "optimize"}
        assert finished.upstream_task_ids >= {"terminate-emr-cluster"}
        assert finished.trigger_rule == "none_failed_min_one_success"

    def test_gsheets_branch_arms_do_not_use_all_success_on_finished(self):
        dag = DAG(dag_id="term_gsheets_branch", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        branch = EmptyOperator(task_id="check-sheet", dag=dag)
        load = EmptyOperator(task_id="load-raw-sheet", dag=dag)
        dummy = EmptyOperator(task_id="dummy-sheet", dag=dag)
        done = EmptyOperator(task_id="done-sheet", dag=dag, trigger_rule="one_success")
        term = EmptyOperator(
            task_id="terminate-emr-cluster",
            dag=dag,
            trigger_rule="all_done",
        )
        finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        execute >> branch
        branch >> load >> done
        branch >> dummy >> done
        done >> term
        ctx = MagicMock()
        ctx.use_airflow_emr = True

        attach_emr_terminate_cluster_work_prerequisites(
            ctx, term, execute_job_cluster_task=execute
        )

        assert finished.upstream_task_ids >= {
            "load-raw-sheet",
            "dummy-sheet",
            "done-sheet",
        }
        assert finished.trigger_rule == "none_failed_min_one_success"


class TestDatabricksAttachIsNoop:
    def test_databricks_attach_does_not_add_edges(self):
        dag = DAG(dag_id="dbr_noop", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        load = EmptyOperator(task_id="load", dag=dag)
        optimize = EmptyOperator(task_id="optimize", dag=dag)
        jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        execute >> load >> optimize >> jcf

        ctx = MagicMock()
        ctx.use_airflow_emr = False
        engine = MagicMock()
        engine.uses_emr_terminate_after_optimize = False
        ctx.job_cluster_engine = engine

        attach_emr_job_cluster_finished_work_prerequisites(
            ctx, jcf, cluster_completion_sink=jcf
        )
        attach_emr_terminate_cluster_work_prerequisites(
            ctx, jcf, execute_job_cluster_task=execute
        )

        assert jcf.upstream_task_ids == {"optimize"}
        assert not load.upstream_task_ids.intersection({"job-cluster-finished"})

    def test_databricks_sink_by_task_id_even_when_objects_differ(self):
        """Databricks: never wire when sink task_id is job-cluster-finished."""
        dag = DAG(dag_id="dbr_sink_task_id", schedule=None)
        other_dag = DAG(dag_id="dbr_sink_other", schedule=None)
        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        load = EmptyOperator(task_id="load", dag=dag)
        optimize = EmptyOperator(task_id="optimize", dag=dag)
        jcf_on_graph = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        jcf_param = EmptyOperator(task_id="job-cluster-finished", dag=other_dag)
        execute >> load >> optimize >> jcf_on_graph

        ctx = MagicMock()
        ctx.use_airflow_emr = False
        ctx.job_cluster_engine = MagicMock(uses_emr_terminate_after_optimize=False)

        attach_emr_job_cluster_finished_work_prerequisites(
            ctx,
            jcf_param,
            cluster_completion_sink=jcf_on_graph,
        )
        attach_emr_terminate_cluster_work_prerequisites(
            ctx, jcf_on_graph, execute_job_cluster_task=execute
        )

        assert jcf_on_graph.upstream_task_ids == {"optimize"}
        assert not jcf_param.upstream_task_ids

    def test_databricks_dw_query_delta_set_dependencies_no_cycle(self):
        from datetime import datetime

        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_delta_workflow import (
            DwQueryDeltaWorkflow,
        )

        dag = DAG(
            dag_id="dw_agent_contract_dbr",
            schedule=None,
            start_date=datetime(2020, 8, 6),
        )
        with patch.dict("os.environ", {"ENVIRONMENT": "forno"}):
            workflow = DwQueryDeltaWorkflow(
                {"name": "dw_agent_contract", "owner": "Data Agents"},
                {
                    "type": "query_delta",
                    "layer": "dw",
                    "custom_schema": "agent",
                    "default_extraction_type": "full",
                    "inner_dependencies": {
                        "fact_agent_contract": ["dim_work_contract"],
                        "fact_daily_accredited_agent": ["fact_agent_contract"],
                    },
                },
                {
                    "type": "consolidation_m_general_cluster",
                    "databricks_conn_id": "databricks_new_env",
                },
            )
            workflow.config_service = MagicMock()
            workflow.config_service._deep_update = lambda a, b: {**a, **(b or {})}
            workflow.config_service.get_config.side_effect = lambda key: {
                "dw_bucket": "dw-bucket",
                "consolidation_m_general_cluster": {
                    "spark_version": "16.4.x-scala2.12"
                },
                "databricks_bietlejuice_repo_path": "s3://repo",
                "default_access_control_list": [],
                "default_libraries": [],
            }.get(key, {})
            ctx = workflow._get_dag_execution_context(dag, "dw-bucket")

        assert not ctx.use_airflow_emr

        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        optimize = EmptyOperator(task_id="optimize-dw", dag=dag)

        dim_load = EmptyOperator(task_id="load-dim_work_contract", dag=dag)
        dim_add_default = EmptyOperator(
            task_id="add-default-dim_work_contract", dag=dag
        )
        fact_load = EmptyOperator(task_id="load-fact_agent_contract", dag=dag)
        daily_load = EmptyOperator(task_id="load-fact_daily_accredited_agent", dag=dag)

        table_first_tasks = {
            "dim_work_contract": dim_load,
            "fact_agent_contract": fact_load,
            "fact_daily_accredited_agent": daily_load,
        }
        table_last_tasks = {
            "dim_work_contract": dim_add_default,
            "fact_agent_contract": fact_load,
            "fact_daily_accredited_agent": daily_load,
        }

        workflow._set_dependencies(
            ctx,
            execute,
            table_first_tasks,
            table_last_tasks,
            optimize,
            jcf,
        )

        list(dag.topological_sort())
        assert jcf.upstream_task_ids == {"optimize-dw"}
        assert "terminate-emr-cluster" not in {t.task_id for t in dag.tasks}


class TestEmrDwQueryDeltaInnerDepsNoCycle:
    def test_emr_dw_query_delta_inner_deps_no_cycle(self):
        from datetime import datetime

        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_delta_workflow import (
            DwQueryDeltaWorkflow,
        )

        dag = DAG(
            dag_id="dw_agent_contract_cycle",
            schedule=None,
            start_date=datetime(2020, 8, 6),
        )
        with patch.dict("os.environ", {"ENVIRONMENT": "forno"}):
            workflow = DwQueryDeltaWorkflow(
                {"name": "dw_agent_contract", "owner": "Data Agents"},
                {
                    "type": "query_delta",
                    "layer": "dw",
                    "custom_schema": "agent",
                    "default_extraction_type": "full",
                    "inner_dependencies": {
                        "fact_agent_contract": ["dim_work_contract"],
                        "fact_daily_accredited_agent": ["fact_agent_contract"],
                    },
                },
                {"type": "emr_7_12_consolidation_xs_memory_cluster"},
            )
            workflow.config_service = MagicMock()
            workflow.config_service._deep_update = lambda a, b: {**a, **(b or {})}
            workflow.config_service.get_config.side_effect = lambda key: {
                "dw_bucket": "dw-bucket",
                "emr_7_12_consolidation_xs_memory_cluster": {
                    "spark_version": "emr-7-12"
                },
                "databricks_bietlejuice_repo_path": "s3://repo",
                "default_access_control_list": [],
                "default_libraries": [],
            }.get(key, {})
            ctx = workflow._get_dag_execution_context(dag, "dw-bucket")

        assert ctx.use_airflow_emr

        execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
        jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
        optimize = EmptyOperator(task_id="optimize-dw", dag=dag)
        term = EmptyOperator(task_id="terminate-emr-cluster", dag=dag)

        dim_load = EmptyOperator(task_id="load-dim_work_contract", dag=dag)
        dim_add_default = EmptyOperator(
            task_id="add-default-dim_work_contract", dag=dag
        )
        dim_register = EmptyOperator(task_id="register-dim_work_contract", dag=dag)
        dim_sync = EmptyOperator(task_id="sync-dim_work_contract", dag=dag)

        fact_load = EmptyOperator(task_id="load-fact_agent_contract", dag=dag)
        fact_register = EmptyOperator(task_id="register-fact_agent_contract", dag=dag)
        fact_sync = EmptyOperator(task_id="sync-fact_agent_contract", dag=dag)

        daily_load = EmptyOperator(task_id="load-fact_daily_accredited_agent", dag=dag)
        daily_register = EmptyOperator(
            task_id="register-fact_daily_accredited_agent", dag=dag
        )
        daily_sync = EmptyOperator(task_id="sync-fact_daily_accredited_agent", dag=dag)

        execute >> dim_load >> dim_add_default >> fact_load
        dim_load >> dim_register >> dim_sync >> optimize
        fact_load >> fact_register >> fact_sync >> optimize
        daily_load >> daily_register >> daily_sync >> optimize
        optimize >> term

        table_first_tasks = {
            "dim_work_contract": dim_load,
            "fact_agent_contract": fact_load,
            "fact_daily_accredited_agent": daily_load,
        }
        table_last_tasks = {
            "dim_work_contract": dim_add_default,
            "fact_agent_contract": fact_load,
            "fact_daily_accredited_agent": daily_load,
        }

        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_delta_workflow.get_job_cluster_completion_sink",
            return_value=term,
        ):
            workflow._set_dependencies(
                ctx,
                execute,
                table_first_tasks,
                table_last_tasks,
                optimize,
                jcf,
            )

        list(dag.topological_sort())
