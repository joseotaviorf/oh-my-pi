"""Compute engine abstraction for job-cluster DAGs: Databricks vs EMR Airflow operators."""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import timedelta
from typing import Any, Dict, List, Optional, Sequence

from airflow.models.baseoperator import BaseOperator
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

from bietlejuice.base.airflow.cluster_config_resolver import (
    resolve_airflow_compute_mode,
)
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.databricks.cluster_env_vars_helper import ClusterEnvVarsHelper
from bietlejuice.base.databricks.spark_event_log_cluster import (
    apply_validation_event_log_overrides,
)
from bietlejuice.services.configuration_service import ConfigurationService

_EXECUTE_JOB_CLUSTER_TASK_ID = "execute-job-cluster"

_DEFAULT_EMR_TASK_RETRIES = 3

_EMR_EXTRA_SPARK_SUBMIT_ARGS = [
    "--conf",
    "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension",
    "--conf",
    "spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog",
    "--conf",
    "spark.hadoop.fs.s3a.acl.default=BucketOwnerFullControl",
    "--conf",
    "spark.hadoop.fs.s3a.canned.acl=BucketOwnerFullControl",
    "--conf",
    "spark.yarn.appMasterEnv.SPARK_RUNTIME=emr",
    "--conf",
    "spark.driverEnv.SPARK_RUNTIME=emr",
]


class JobClusterEngine(ABC):
    """Abstracts Databricks job cluster vs EMR create/submit/terminate for DAG builders."""

    def __init__(self, dag_execution_context: DagExecutionContext) -> None:
        self._ctx = dag_execution_context

    @abstractmethod
    def create_execute_cluster_task(
        self,
        *,
        config_service: ConfigurationService,
        minimum_cluster_runtime_version: Optional[str],
        execute_job_cluster_local_id: Optional[int],
    ) -> BaseOperator:
        """``minimum_cluster_runtime_version`` is enforced on Databricks; ignored on EMR."""
        pass

    @abstractmethod
    def create_spark_python_task(
        self,
        *,
        spark_job_path: str,
        task_id: str,
        job_parameters: List[Any],
        execution_timeout_hours: int,
    ) -> BaseOperator:
        pass

    @property
    def uses_emr_terminate_after_optimize(self) -> bool:
        return False

    def create_emr_terminate_cluster_task(
        self,
        *,
        execute_cluster_task_id: str,
        terminate_task_local_suffix: Optional[int],
    ) -> BaseOperator:
        raise NotImplementedError


class DatabricksJobClusterEngine(JobClusterEngine):
    """Databricks job cluster: ExecuteJobCluster + CheckJob tasks (existing behavior)."""

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        config_service: ConfigurationService,
    ) -> None:
        super().__init__(dag_execution_context)
        self._config_service = config_service

    def _get_access_control_list(self) -> list:
        acl = self._ctx.cluster_args.get("access_control_list")
        if acl is None:
            cluster_type = self._ctx.cluster_args.get("type")
            if cluster_type:
                cluster_template = self._config_service.get_config(cluster_type)
                acl = cluster_template.get("access_control_list")
        if acl is None:
            acl = self._config_service.get_config("default_access_control_list")[0]
        if isinstance(acl, dict):
            return [acl]
        return acl

    def _get_cluster_configuration(self) -> dict:
        cluster_type = self._ctx.cluster_args.get("type")
        cluster_configuration = self._config_service.get_config(cluster_type)
        return self._config_service._deep_update(
            cluster_configuration,
            self._ctx.cluster_args.get("custom_configurations", {}),
        )

    def _validate_minimum_cluster_runtime_version(
        self,
        cluster_configuration: dict,
        minimum_cluster_runtime_version: Optional[str],
    ) -> None:
        if not minimum_cluster_runtime_version:
            return
        current_runtime_version = cluster_configuration.get("spark_version")
        current_major = int(current_runtime_version.split(".")[0])
        current_minor = int(current_runtime_version.split(".")[1])
        min_major = int(minimum_cluster_runtime_version.split(".")[0])
        min_minor = int(minimum_cluster_runtime_version.split(".")[1])
        if current_major < min_major or (
            current_major == min_major and current_minor < min_minor
        ):
            raise ValueError(
                f"Current cluster runtime ({current_runtime_version}) is below "
                f"the minimum required version ({minimum_cluster_runtime_version})"
            )

    def _get_libraries(self) -> list:
        default_libraries = self._config_service.get_config("default_libraries")
        custom_libraries = [
            (
                {
                    lib_type: lib_name.format(
                        artifacts_bucket=self._config_service.get_config(
                            "artifacts_bucket"
                        )
                    )
                }
                if isinstance(lib_name, str)
                else {lib_type: lib_name}
            )
            for custom_libraries in self._ctx.cluster_args.get("custom_libraries", [])
            for lib_type, lib_name in custom_libraries.items()
        ]
        return default_libraries + custom_libraries

    def _input_databricks_default_service_credential_name(
        self, cluster_configuration: dict
    ) -> dict:
        dbr_version = cluster_configuration["spark_version"]
        data_security_mode = cluster_configuration["data_security_mode"]

        if data_security_mode == "USER_ISOLATION" and dbr_version >= "16.4":
            cluster_configuration["spark_env_vars"][
                "DATABRICKS_DEFAULT_SERVICE_CREDENTIAL_NAME"
            ] = self._config_service.get_config(
                "databricks_default_service_credential_name"
            )
        return cluster_configuration

    def _input_spark_env_vars(self, cluster_configuration: dict) -> dict:
        cluster_configuration = ClusterEnvVarsHelper.input_spark_env_vars(
            cluster_configuration
        )
        cluster_configuration = self._input_databricks_default_service_credential_name(
            cluster_configuration
        )
        return cluster_configuration

    def create_execute_cluster_task(
        self,
        *,
        config_service: ConfigurationService,
        minimum_cluster_runtime_version: Optional[str],
        execute_job_cluster_local_id: Optional[int],
    ) -> BaseOperator:
        _ = config_service
        cluster_configuration = self._get_cluster_configuration()
        cluster_configuration = self._input_spark_env_vars(cluster_configuration)
        if self._ctx.is_validation:
            cluster_configuration = apply_validation_event_log_overrides(
                cluster_configuration
            )
        self._validate_minimum_cluster_runtime_version(
            cluster_configuration, minimum_cluster_runtime_version
        )
        if execute_job_cluster_local_id:
            task_id = f"{_EXECUTE_JOB_CLUSTER_TASK_ID}-{execute_job_cluster_local_id}"
        else:
            task_id = _EXECUTE_JOB_CLUSTER_TASK_ID

        return QuintoAndarDatabricksExecuteJobClusterOperator(
            databricks_conn_id=self._ctx.databricks_conn_id,
            dag=self._ctx.dag,
            task_id=task_id,
            cluster_configuration=cluster_configuration,
            libraries=self._get_libraries(),
            access_control_list=self._get_access_control_list(),
            execution_timeout=timedelta(
                hours=BaseTaskCreator._DEFAULT_EXECUTION_TIMEOUT_HOURS
            ),
        )

    def create_spark_python_task(
        self,
        *,
        spark_job_path: str,
        task_id: str,
        job_parameters: List[Any],
        execution_timeout_hours: int,
    ) -> BaseOperator:
        return QuintoAndarDatabricksCheckJobTaskOperator(
            databricks_conn_id=self._ctx.databricks_conn_id,
            dag=self._ctx.dag,
            task_id=task_id,
            json={
                "spark_python_task": {
                    "python_file": spark_job_path,
                    "parameters": job_parameters,
                }
            },
            execution_timeout=timedelta(hours=execution_timeout_hours),
        )


class EmrJobClusterEngine(JobClusterEngine):
    """EMR: create cluster, spark-submit per task, terminate after optimize."""

    def _emr_operator_retry_kwargs(self) -> Dict[str, Any]:
        if self._ctx.is_validation:
            return {"retries": 0}
        cluster = self._ctx.cluster_args
        kwargs: Dict[str, Any] = {
            "retries": cluster.get("emr_task_retries", _DEFAULT_EMR_TASK_RETRIES),
        }
        delay_seconds = cluster.get("emr_retry_delay_seconds")
        if delay_seconds is not None:
            kwargs["retry_delay"] = timedelta(seconds=int(delay_seconds))
        return kwargs

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        merged_cluster_configuration: Dict[str, Any],
        config_service: ConfigurationService,
    ) -> None:
        super().__init__(dag_execution_context)
        self._merged_cluster_configuration = merged_cluster_configuration
        self._config_service = config_service

    @property
    def uses_emr_terminate_after_optimize(self) -> bool:
        return True

    def create_execute_cluster_task(
        self,
        *,
        config_service: ConfigurationService,
        minimum_cluster_runtime_version: Optional[str],
        execute_job_cluster_local_id: Optional[int],
    ) -> BaseOperator:
        _ = minimum_cluster_runtime_version
        _ = config_service
        if execute_job_cluster_local_id:
            task_id = f"{_EXECUTE_JOB_CLUSTER_TASK_ID}-{execute_job_cluster_local_id}"
        else:
            task_id = _EXECUTE_JOB_CLUSTER_TASK_ID

        self._ctx.emr_active_create_cluster_task_id = task_id

        from emr_plugin import QuintoAndarEmrCreateClusterOperator

        return QuintoAndarEmrCreateClusterOperator(
            task_id=task_id,
            cluster_configuration=dict(self._merged_cluster_configuration),
            aws_conn_id=self._ctx.aws_conn_id,
            dag=self._ctx.dag,
            execution_timeout=timedelta(
                hours=BaseTaskCreator._DEFAULT_EXECUTION_TIMEOUT_HOURS
            ),
            **self._emr_operator_retry_kwargs(),
        )

    def create_spark_python_task(
        self,
        *,
        spark_job_path: str,
        task_id: str,
        job_parameters: List[Any],
        execution_timeout_hours: int,
    ) -> BaseOperator:
        create_id = self._ctx.emr_active_create_cluster_task_id
        if not create_id:
            raise ValueError(
                "emr_active_create_cluster_task_id must be set before creating EMR spark tasks"
            )
        job_flow_id = "{{ task_instance.xcom_pull(task_ids='" + create_id + "') }}"
        from emr_plugin import QuintoAndarEmrSubmitStepsOperator

        step = QuintoAndarEmrSubmitStepsOperator.build_spark_submit_step(
            name=task_id,
            script_uri=spark_job_path,
            args=[str(p) for p in job_parameters],
            extra_spark_args=list(_EMR_EXTRA_SPARK_SUBMIT_ARGS)
            + [
                "--conf",
                f"spark.openlineage.parentJobName={{{{ dag.dag_id }}}}.{task_id}",
                "--conf",
                "spark.openlineage.parentJobNamespace=airflow",
            ],
        )
        return QuintoAndarEmrSubmitStepsOperator(
            task_id=task_id,
            job_flow_id=job_flow_id,
            steps=[step],
            wait_for_completion=True,
            aws_conn_id=self._ctx.aws_conn_id,
            dag=self._ctx.dag,
            execution_timeout=timedelta(hours=execution_timeout_hours),
            **self._emr_operator_retry_kwargs(),
        )

    def create_emr_terminate_cluster_task(
        self,
        *,
        execute_cluster_task_id: str,
        terminate_task_local_suffix: Optional[int],
    ) -> BaseOperator:
        tid = "terminate-emr-cluster"
        if terminate_task_local_suffix is not None and terminate_task_local_suffix > 1:
            tid = f"{tid}-{terminate_task_local_suffix}"
        job_flow_id = (
            "{{ task_instance.xcom_pull(task_ids='" + execute_cluster_task_id + "') }}"
        )
        from emr_plugin import QuintoAndarEmrTerminateClusterOperator

        return QuintoAndarEmrTerminateClusterOperator(
            task_id=tid,
            job_flow_id=job_flow_id,
            aws_conn_id=self._ctx.aws_conn_id,
            trigger_rule="all_done",
            deferrable=True,
            dag=self._ctx.dag,
            **self._emr_operator_retry_kwargs(),
        )


def get_job_cluster_completion_sink(
    dag_execution_context: DagExecutionContext,
    execute_job_cluster_task: BaseOperator,
    job_cluster_finished_task: BaseOperator,
    execute_job_cluster_local_id: Optional[int] = None,
) -> BaseOperator:
    """
    Returns the task upstream work should link to before ``job-cluster-finished``.

    Databricks: returns ``job_cluster_finished_task`` (job ends / autotermination).

    EMR: creates ``terminate-emr-cluster`` (or suffixed), wires it to
    ``job_cluster_finished_task``, and returns the terminate task so Spark work
    flows ``... >> terminate >> job-cluster-finished``.
    """
    engine = dag_execution_context.job_cluster_engine
    if engine is None or not engine.uses_emr_terminate_after_optimize:
        return job_cluster_finished_task
    terminate_suffix = None
    if execute_job_cluster_local_id is not None and execute_job_cluster_local_id > 1:
        terminate_suffix = execute_job_cluster_local_id
    emr_terminate_task = engine.create_emr_terminate_cluster_task(
        execute_cluster_task_id=execute_job_cluster_task.task_id,
        terminate_task_local_suffix=terminate_suffix,
    )
    emr_terminate_task.set_downstream(job_cluster_finished_task)
    return emr_terminate_task


def attach_emr_job_cluster_finished_work_prerequisites(
    dag_execution_context: DagExecutionContext,
    job_cluster_finished_task: BaseOperator,
    work_completion_tasks: Optional[Sequence[BaseOperator]] = None,
    *,
    cluster_completion_sink: Optional[BaseOperator] = None,
) -> None:
    """
    EMR: ``job-cluster-finished`` must not succeed on failed Spark/EMR work, but
    ``terminate-emr-cluster`` is ``all_done`` and always succeeds if the API
    call works. Add direct upstreams from the work tasks that must succeed
    (same set that feeds the cluster completion sink) so the finished task
    uses the default ``all_success`` and reflects failures. No-op on Databricks.

    Pass **either** ``work_completion_tasks`` **or** ``cluster_completion_sink``
    (not both). When ``cluster_completion_sink`` is set, direct upstreams of
    the sink (usually ``terminate-emr-*``) are used—call this after all edges to
    the sink are wired. If the sink is already ``job-cluster-finished`` (e.g.
    Databricks), the function is a no-op.
    """
    if not dag_execution_context.use_airflow_emr:
        return
    if work_completion_tasks is not None and cluster_completion_sink is not None:
        raise ValueError(
            "Pass at most one of work_completion_tasks or cluster_completion_sink"
        )
    if cluster_completion_sink is not None:
        if cluster_completion_sink is job_cluster_finished_task:
            return
        work_completion_tasks = list(cluster_completion_sink.upstream_list)
    elif not work_completion_tasks:
        return
    for task in work_completion_tasks:
        job_cluster_finished_task.set_upstream(task)


def build_job_cluster_engine(
    dag_execution_context: DagExecutionContext,
    config_service: ConfigurationService,
) -> JobClusterEngine:
    use_emr, merged = resolve_airflow_compute_mode(
        dag_execution_context.cluster_args, config_service
    )
    dag_execution_context.use_airflow_emr = use_emr
    dag_execution_context.aws_conn_id = dag_execution_context.cluster_args.get(
        "aws_conn_id", "aws_default"
    )
    if use_emr:
        if dag_execution_context.is_validation:
            merged = apply_validation_event_log_overrides(merged)
        return EmrJobClusterEngine(dag_execution_context, merged, config_service)
    return DatabricksJobClusterEngine(dag_execution_context, config_service)


def attach_job_cluster_engine_to_context(
    dag_execution_context: DagExecutionContext,
    config_service: ConfigurationService,
) -> None:
    dag_execution_context.job_cluster_engine = build_job_cluster_engine(
        dag_execution_context, config_service
    )
