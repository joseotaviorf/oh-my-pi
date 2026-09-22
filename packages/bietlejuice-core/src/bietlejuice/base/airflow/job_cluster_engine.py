"""Compute engine abstraction for job-cluster DAGs: Databricks vs EMR Airflow operators."""

from __future__ import annotations

import copy
import logging
from abc import ABC, abstractmethod
from collections import deque
from datetime import timedelta
from typing import Any, Deque, Dict, List, Optional, Sequence, Union

from airflow.models.baseoperator import BaseOperator
from airflow.utils.task_group import TaskGroup
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.cluster_config_resolver import (
    apply_custom_configurations,
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
from bietlejuice.base.validation.spark_args import encode_cli_arg
from bietlejuice.services.configuration_service import ConfigurationService

_EXECUTE_JOB_CLUSTER_TASK_ID = "execute-job-cluster"
_CREATE_CLUSTER_TASK_ID = "create-cluster"
_TERMINATE_CLUSTER_TASK_ID = "terminate-cluster"

# Merged cluster YAML (preset + declaration ``custom_configurations``) may set this to
# ``false`` to opt a cluster OUT of deferrable EMR waits; deferrable is the default.
# Stripped before EMR translate / create-cluster API payload. Not an EMR API field.
_AIRFLOW_EMR_CREATE_CLUSTER_DEFERRABLE = "airflow_emr_create_cluster_deferrable"

_DEFAULT_EMR_TASK_RETRIES = 3

_DELTA_SPARK_SQL_EXTENSIONS = "io.delta.sql.DeltaSparkSessionExtension"

# Cluster spark_conf keys forwarded to spark-submit when set on the merged cluster.
_EMR_STEP_SPARK_CONF_KEYS = (
    "spark.kryo.registrator",
    "spark.serializer",
)

# Per-step Spark resource profile for accessory tasks. Appended LAST in
# `extra_spark_args` so `spark-submit --conf` overrides cluster `spark-defaults`.
# Only consumed by ``EmrJobClusterEngine``; Databricks tasks ignore the profile
# because per-task resource overrides are not supported by the CheckJob API.

# Register-table (driver-only Trino REST) and sync-metadata (driver + minimal
# `df.foreach` over a tiny table-name DataFrame for Hive/metadata-propagator
# fanout) are I/O-bound accessory tasks with negligible executor compute.
# Cap at 1 executor / 1g / 1 core so they do not queue behind heavy load
# tasks for cluster-default 8g executor slots. `minExecutors=1` keeps the
# single executor pre-warmed to avoid YARN allocation lag on the foreach.
METADATA_TASK_LIGHTWEIGHT_SPARK_CONF: Dict[str, str] = {
    "spark.driver.memory": "1g",
    "spark.driver.memoryOverhead": "512m",
    "spark.executor.memory": "1g",
    "spark.executor.memoryOverhead": "384m",
    "spark.executor.cores": "1",
    "spark.yarn.am.memory": "512m",
    "spark.yarn.am.cores": "1",
    "spark.dynamicAllocation.minExecutors": "1",
    "spark.dynamicAllocation.maxExecutors": "1",
}


def _spark_conf_to_submit_args(spark_conf: Optional[Dict[str, str]]) -> List[str]:
    """Flatten ``{key: value}`` into ``["--conf", "key=value", ...]`` for spark-submit."""
    if not spark_conf:
        return []
    args: List[str] = []
    for key, value in spark_conf.items():
        args.extend(["--conf", f"{key}={value}"])
    return args


def _merge_spark_sql_extensions(*extension_lists: Optional[str]) -> str:
    """Join comma-separated extension class names without duplicates."""
    merged: List[str] = []
    for extension_list in extension_lists:
        if not extension_list:
            continue
        for extension in extension_list.split(","):
            extension = extension.strip()
            if extension and extension not in merged:
                merged.append(extension)
    return ",".join(merged)


def _effective_cluster_spark_conf(
    cluster_configuration: Dict[str, Any],
) -> Dict[str, Any]:
    """Top-level spark_conf plus custom_configurations.spark_conf overlay."""
    spark_conf = dict(cluster_configuration.get("spark_conf") or {})
    custom_configurations = cluster_configuration.get("custom_configurations") or {}
    custom_spark_conf = custom_configurations.get("spark_conf")
    if isinstance(custom_spark_conf, dict):
        spark_conf = {**spark_conf, **custom_spark_conf}
    return spark_conf


def _build_emr_extra_spark_submit_args(
    cluster_configuration: Dict[str, Any],
) -> List[str]:
    """Delta defaults plus optional cluster spark_conf (e.g. additional SQL session extensions)."""
    spark_conf = _effective_cluster_spark_conf(cluster_configuration)
    cluster_extensions = spark_conf.get("spark.sql.extensions")
    merged_extensions = _merge_spark_sql_extensions(
        _DELTA_SPARK_SQL_EXTENSIONS,
        cluster_extensions,
    )
    args: List[str] = [
        "--conf",
        f"spark.sql.extensions={merged_extensions}",
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
    for key in _EMR_STEP_SPARK_CONF_KEYS:
        value = spark_conf.get(key)
        if value is not None:
            args.extend(["--conf", f"{key}={value}"])
    return args


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
        python_interpreter_path: Optional[str] = None,
        task_spark_conf: Optional[Dict[str, str]] = None,
        py_files: Optional[str] = None,
        do_output_xcom_push: bool = False,
        pool: Optional[str] = None,
    ) -> BaseOperator:
        """``python_interpreter_path`` runs the step on the given Python
        interpreter on EMR (sets ``spark.pyspark.[driver.]python``); ignored on
        Databricks, where the interpreter is cluster-level.

        ``task_spark_conf`` injects per-step ``spark-submit --conf`` overrides on
        EMR (appended last so they win over cluster ``spark-defaults``). Ignored
        on Databricks, which does not support per-task resource overrides.

        ``py_files`` passes a comma-separated ``--py-files`` value to EMR
        spark-submit, for spark job packages with sibling modules the single
        entry-point script can't otherwise import. Ignored on Databricks,
        whose job cluster resolves the whole package from the workspace."""
        pass

    @property
    def uses_emr_terminate_after_optimize(self) -> bool:
        return False

    def create_databricks_terminate_cluster_task(self) -> BaseOperator:
        """Databricks all-purpose cluster teardown (``terminate-cluster``)."""
        raise NotImplementedError

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
        # Deep-copy: HierarchicalConf.get_config returns nested dicts by reference,
        # and _deep_update mutates its source. Without a copy, shared presets
        # (e.g. Wonka's single ConfigurationService) would accumulate per-DAG
        # custom_configurations across builds in the same parse process.
        cluster_configuration = copy.deepcopy(
            self._config_service.get_config(cluster_type)
        )
        return apply_custom_configurations(
            cluster_configuration,
            self._ctx.cluster_args.get("custom_configurations", {}),
            self._config_service,
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
        # EMR-only pypi keys (no_deps, only_binary) must not be sent to Databricks.
        _pypi_databricks_keys = frozenset({"package", "repo"})
        custom_libraries = []
        for custom_library in self._ctx.cluster_args.get("custom_libraries", []):
            for lib_type, lib_name in custom_library.items():
                if isinstance(lib_name, str):
                    custom_libraries.append(
                        {
                            lib_type: lib_name.format(
                                artifacts_bucket=self._config_service.get_config(
                                    "artifacts_bucket"
                                )
                            )
                        }
                    )
                elif lib_type == "pypi" and isinstance(lib_name, dict):
                    cleaned = {
                        key: value
                        for key, value in lib_name.items()
                        if key in _pypi_databricks_keys
                    }
                    custom_libraries.append({lib_type: cleaned})
                else:
                    custom_libraries.append({lib_type: lib_name})
        return default_libraries + custom_libraries

    def _input_databricks_default_service_credential_name(
        self, cluster_configuration: dict
    ) -> dict:
        dbr_version = cluster_configuration.get("spark_version")
        data_security_mode = cluster_configuration.get("data_security_mode")
        # EMR (and mis-routed configs) have no data_security_mode — skip quietly.
        if (
            data_security_mode == "USER_ISOLATION"
            and dbr_version
            and dbr_version >= "16.4"
        ):
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
        python_interpreter_path: Optional[str] = None,
        task_spark_conf: Optional[Dict[str, str]] = None,
        py_files: Optional[str] = None,
        do_output_xcom_push: bool = False,
        pool: Optional[str] = None,
    ) -> BaseOperator:

        if python_interpreter_path is not None:
            logging.warning(
                "[DatabricksJobClusterEngine] The 'python_interpreter_path' argument"
                " is ignored in Databricks: interpreter is set at the cluster level."
            )

        if task_spark_conf:
            logging.debug(
                "[DatabricksJobClusterEngine] Ignoring task_spark_conf for task %s: "
                "per-task resource overrides are not supported by the CheckJob API.",
                task_id,
            )

        _ = python_interpreter_path
        _ = task_spark_conf
        _ = py_files

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


class DatabricksTaskSubmissionEngine(DatabricksJobClusterEngine):
    """Databricks all-purpose cluster: CreateCluster + SubmitRun + Terminate.

    Used by classic ``gsheets`` DAGs to preserve task submission (``existing_cluster_id``)
    instead of ephemeral job clusters (ExecuteJobCluster + CheckJob).
    """

    def create_execute_cluster_task(
        self,
        *,
        config_service: ConfigurationService,
        minimum_cluster_runtime_version: Optional[str],
        execute_job_cluster_local_id: Optional[int],
    ) -> BaseOperator:
        _ = config_service
        _ = execute_job_cluster_local_id
        cluster_configuration = self._get_cluster_configuration()
        cluster_configuration = self._input_spark_env_vars(cluster_configuration)
        if self._ctx.is_validation:
            cluster_configuration = apply_validation_event_log_overrides(
                cluster_configuration
            )
        self._validate_minimum_cluster_runtime_version(
            cluster_configuration, minimum_cluster_runtime_version
        )

        return QuintoAndarDatabricksCreateClusterOperator(
            databricks_conn_id=self._ctx.databricks_conn_id,
            dag=self._ctx.dag,
            task_id=_CREATE_CLUSTER_TASK_ID,
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
        python_interpreter_path: Optional[str] = None,
        task_spark_conf: Optional[Dict[str, str]] = None,
        py_files: Optional[str] = None,
        do_output_xcom_push: bool = False,
        pool: Optional[str] = None,
    ) -> BaseOperator:
        if python_interpreter_path is not None:
            logging.warning(
                "[DatabricksTaskSubmissionEngine] The 'python_interpreter_path' argument"
                " is ignored: interpreter is set at the cluster level."
            )
        if task_spark_conf:
            logging.debug(
                "[DatabricksTaskSubmissionEngine] Ignoring task_spark_conf for task %s.",
                task_id,
            )
        if py_files:
            logging.debug(
                "[DatabricksTaskSubmissionEngine] Ignoring py_files for task %s.",
                task_id,
            )

        operator_kwargs: Dict[str, Any] = {
            "task_id": task_id,
            "dag": self._ctx.dag,
            "json": {
                "spark_python_task": {
                    "python_file": spark_job_path,
                    "parameters": job_parameters,
                }
            },
            "do_output_xcom_push": do_output_xcom_push,
            "execution_timeout": timedelta(hours=execution_timeout_hours),
            "databricks_conn_id": self._ctx.databricks_conn_id,
        }
        if pool is not None:
            operator_kwargs["pool"] = pool

        return QuintoAndarDatabricksSubmitRunOperator(**operator_kwargs)

    def create_databricks_terminate_cluster_task(self) -> BaseOperator:
        return QuintoAndarDatabricksTerminateClusterOperator(
            dag=self._ctx.dag,
            task_id=_TERMINATE_CLUSTER_TASK_ID,
            trigger_rule="all_done",
            databricks_conn_id=self._ctx.databricks_conn_id,
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

    def _emr_deferrable_kwargs(self) -> Dict[str, Any]:
        return {
            "deferrable": bool(
                self._merged_cluster_configuration.get(
                    _AIRFLOW_EMR_CREATE_CLUSTER_DEFERRABLE, True
                )
            )
        }

    @staticmethod
    def _strip_emr_deferrable_key(cluster_configuration: Dict[str, Any]) -> None:
        cluster_configuration.pop(_AIRFLOW_EMR_CREATE_CLUSTER_DEFERRABLE, None)

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

        cluster_configuration = dict(self._merged_cluster_configuration)
        self._strip_emr_deferrable_key(cluster_configuration)
        cluster_configuration = ClusterEnvVarsHelper.input_emr_yarn_env_vars(
            cluster_configuration
        )

        return QuintoAndarEmrCreateClusterOperator(
            task_id=task_id,
            cluster_configuration=cluster_configuration,
            aws_conn_id=self._ctx.aws_conn_id,
            dag=self._ctx.dag,
            execution_timeout=timedelta(
                hours=BaseTaskCreator._DEFAULT_EXECUTION_TIMEOUT_HOURS
            ),
            **self._emr_operator_retry_kwargs(),
            **self._emr_deferrable_kwargs(),
        )

    @staticmethod
    def _python_interpreter_spark_args(
        python_interpreter_path: Optional[str],
    ) -> List[str]:
        """Per-step interpreter override; empty unless a path is given."""
        if not python_interpreter_path:
            return []
        return [
            "--conf",
            f"spark.pyspark.python={python_interpreter_path}",
            "--conf",
            f"spark.pyspark.driver.python={python_interpreter_path}",
        ]

    def create_spark_python_task(
        self,
        *,
        spark_job_path: str,
        task_id: str,
        job_parameters: List[Any],
        execution_timeout_hours: int,
        python_interpreter_path: Optional[str] = None,
        task_spark_conf: Optional[Dict[str, str]] = None,
        py_files: Optional[str] = None,
        do_output_xcom_push: bool = False,
        pool: Optional[str] = None,
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
            args=[encode_cli_arg(p) for p in job_parameters],
            deploy_mode=str(
                self._merged_cluster_configuration.get("emr_deploy_mode", "client")
            ),
            # task_spark_conf appended LAST so its --conf entries override any
            # matching keys emitted earlier (Delta defaults, OpenLineage,
            # cluster spark-defaults). spark-submit takes the last --conf per key.
            extra_spark_args=(["--py-files", py_files] if py_files else [])
            + _build_emr_extra_spark_submit_args(self._merged_cluster_configuration)
            + self._python_interpreter_spark_args(python_interpreter_path)
            + [
                "--conf",
                f"spark.openlineage.parentJobName={{{{ dag.dag_id }}}}.{task_id}",
                "--conf",
                "spark.openlineage.parentJobNamespace=airflow",
            ]
            + _spark_conf_to_submit_args(task_spark_conf),
        )
        operator_kwargs: Dict[str, Any] = {
            "task_id": task_id,
            "job_flow_id": job_flow_id,
            "steps": [step],
            "wait_for_completion": True,
            "aws_conn_id": self._ctx.aws_conn_id,
            "dag": self._ctx.dag,
            "execution_timeout": timedelta(hours=execution_timeout_hours),
            **self._emr_operator_retry_kwargs(),
            **self._emr_deferrable_kwargs(),
        }
        if pool is not None:
            operator_kwargs["pool"] = pool
        return QuintoAndarEmrSubmitStepsOperator(**operator_kwargs)

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
            dag=self._ctx.dag,
            **self._emr_operator_retry_kwargs(),
            **self._emr_deferrable_kwargs(),
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
    # terminate >> job-cluster-finished is wired in attach_emr_terminate_cluster_work_prerequisites
    # so job-cluster-finished is never downstream of execute during work-task collection.
    return emr_terminate_task


_EMR_TERMINAL_TASK_ID_PREFIXES = (
    "job-cluster-finished",
    "terminate-emr-cluster",
)


def _is_emr_terminal_task_id(task_id: str) -> bool:
    return task_id.startswith(_EMR_TERMINAL_TASK_ID_PREFIXES)


def _is_emr_terminate_sink(sink: BaseOperator) -> bool:
    return sink.task_id.startswith("terminate-emr-cluster")


def _is_job_cluster_finished_sink(sink: BaseOperator) -> bool:
    return sink.task_id.startswith("job-cluster-finished")


def _emr_terminate_wiring_enabled(
    dag_execution_context: DagExecutionContext,
    cluster_completion_sink: BaseOperator,
) -> bool:
    """True only when the DAG uses an EMR terminate-emr-cluster completion sink."""
    if not dag_execution_context.use_airflow_emr:
        return False
    engine = dag_execution_context.job_cluster_engine
    if engine is None or not engine.uses_emr_terminate_after_optimize:
        return False
    return _is_emr_terminate_sink(cluster_completion_sink)


def _is_cluster_completion_sink_node(
    node: Union[BaseOperator, TaskGroup],
    cluster_completion_sink: BaseOperator,
) -> bool:
    if node is cluster_completion_sink:
        return True
    if (
        isinstance(node, BaseOperator)
        and node.task_id == cluster_completion_sink.task_id
    ):
        return True
    return False


def _resolve_job_cluster_finished_task(
    cluster_completion_sink: BaseOperator,
) -> Optional[BaseOperator]:
    for downstream in cluster_completion_sink.downstream_list:
        if isinstance(downstream, BaseOperator) and downstream.task_id.startswith(
            "job-cluster-finished"
        ):
            return downstream
    try:
        return cluster_completion_sink.dag.get_task("job-cluster-finished")
    except Exception:
        return None


def _attach_emr_cluster_work_prerequisites(
    dag_execution_context: DagExecutionContext,
    cluster_completion_sink: BaseOperator,
    *,
    execute_job_cluster_task: BaseOperator,
    job_cluster_finished_task: Optional[BaseOperator] = None,
) -> None:
    if not _emr_terminate_wiring_enabled(
        dag_execution_context, cluster_completion_sink
    ):
        return

    if job_cluster_finished_task is None:
        job_cluster_finished_task = _resolve_job_cluster_finished_task(
            cluster_completion_sink
        )
    if job_cluster_finished_task is None:
        return

    work_tasks = collect_emr_cluster_work_tasks(
        execute_job_cluster_task, cluster_completion_sink
    )
    for task in work_tasks:
        if task is cluster_completion_sink or task is job_cluster_finished_task:
            continue
        if _is_emr_terminal_task_id(task.task_id):
            continue
        cluster_completion_sink.set_upstream(task)
        job_cluster_finished_task.set_upstream(task)

    # Work includes both BranchPythonOperator arms (e.g. classic gsheets). One arm is
    # always skipped, so the default all_success would skip job-cluster-finished.
    # none_failed_min_one_success is the DAG-level analog of done's one_success join:
    # skipped branch arms do not skip the task, but a failed Spark/EMR task still does.
    job_cluster_finished_task.trigger_rule = "none_failed_min_one_success"
    cluster_completion_sink.set_downstream(job_cluster_finished_task)


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
    (same set that feeds the cluster completion sink). The finished task uses
    ``none_failed_min_one_success`` so skipped branch arms (classic gsheets) do
    not skip it, while failed work still does. No-op on Databricks.

    Also call :func:`attach_emr_terminate_cluster_work_prerequisites` with
    ``execute_job_cluster_task`` and ``cluster_completion_sink`` so
    ``terminate-emr-cluster`` waits for all retry attempts (``all_done`` on an
    optimize-only upstream can fire early when optimize is ``upstream_failed``
    while sibling spark tasks are still ``up_for_retry``).

    Pass **either** ``work_completion_tasks`` **or** ``cluster_completion_sink``
    (not both). When ``cluster_completion_sink`` is an EMR ``terminate-emr-*``
    task, this function is a no-op — call
    :func:`attach_emr_terminate_cluster_work_prerequisites` after all edges to the
    sink are wired (it wires both terminate and ``job-cluster-finished``). When
    ``cluster_completion_sink`` is ``job-cluster-finished`` (Databricks), the
    function is a no-op.
    """
    if not dag_execution_context.use_airflow_emr:
        return
    if work_completion_tasks is not None and cluster_completion_sink is not None:
        raise ValueError(
            "Pass at most one of work_completion_tasks or cluster_completion_sink"
        )
    if cluster_completion_sink is not None:
        if _is_job_cluster_finished_sink(cluster_completion_sink):
            return
        if cluster_completion_sink is job_cluster_finished_task:
            return
        if _is_emr_terminate_sink(cluster_completion_sink):
            return
        work_completion_tasks = list(cluster_completion_sink.upstream_list)
    elif not work_completion_tasks:
        return
    for task in work_completion_tasks:
        job_cluster_finished_task.set_upstream(task)


def _operators_in_task_group(task_group: TaskGroup) -> List[BaseOperator]:
    operators: List[BaseOperator] = []
    for child in task_group.children.values():
        if isinstance(child, BaseOperator):
            operators.append(child)
        elif isinstance(child, TaskGroup):
            operators.extend(_operators_in_task_group(child))
    return operators


def collect_emr_cluster_work_tasks(
    execute_job_cluster_task: BaseOperator,
    cluster_completion_sink: BaseOperator,
) -> List[BaseOperator]:
    """
    All tasks downstream of ``execute-job-cluster`` that feed the completion sink,
    stopping before the sink itself. Traverses TaskGroups. Never collects
    ``job-cluster-finished`` or ``terminate-emr-cluster*``.
    """
    collected: List[BaseOperator] = []
    seen: set[str] = set()
    queue: Deque[Union[BaseOperator, TaskGroup]] = deque(
        execute_job_cluster_task.downstream_list
    )

    while queue:
        node = queue.popleft()
        if _is_cluster_completion_sink_node(node, cluster_completion_sink):
            continue
        if isinstance(node, TaskGroup):
            for operator in _operators_in_task_group(node):
                if operator.task_id in seen:
                    continue
                if _is_emr_terminal_task_id(operator.task_id):
                    continue
                seen.add(operator.task_id)
                collected.append(operator)
                for downstream in operator.downstream_list:
                    if not _is_cluster_completion_sink_node(
                        downstream, cluster_completion_sink
                    ):
                        queue.append(downstream)
            for downstream in node.downstream_list:
                if not _is_cluster_completion_sink_node(
                    downstream, cluster_completion_sink
                ):
                    queue.append(downstream)
            continue
        if isinstance(node, BaseOperator):
            if node.task_id in seen:
                continue
            if _is_emr_terminal_task_id(node.task_id):
                continue
            seen.add(node.task_id)
            collected.append(node)
            for downstream in node.downstream_list:
                if not _is_cluster_completion_sink_node(
                    downstream, cluster_completion_sink
                ):
                    queue.append(downstream)

    return collected


def attach_emr_terminate_cluster_work_prerequisites(
    dag_execution_context: DagExecutionContext,
    cluster_completion_sink: BaseOperator,
    *,
    execute_job_cluster_task: BaseOperator,
    job_cluster_finished_task: Optional[BaseOperator] = None,
) -> None:
    """
    EMR: wire every cluster work task directly upstream of ``terminate-emr-cluster``
    and ``job-cluster-finished``, then link ``terminate-emr-cluster >>
    job-cluster-finished``. No-op on Databricks.

    When workflows route ``work >> optimize >> terminate``, optimize may become
    ``upstream_failed`` while parallel loads or accessory tasks (register, sync,
    data_quality, etc.) are still retrying; ``all_done`` on terminate then fires
    early because ``upstream_failed`` counts as done. Collecting all tasks between
    ``execute-job-cluster`` and the completion sink ensures terminate waits until
    every branch finishes all retries. No-op on Databricks.

    Pass ``job_cluster_finished_task`` when the finished task has a non-standard
    task id (i.e. not ``job-cluster-finished``). If omitted, the function resolves
    the finished task by looking for ``job-cluster-finished`` in the DAG.
    """
    _attach_emr_cluster_work_prerequisites(
        dag_execution_context,
        cluster_completion_sink,
        execute_job_cluster_task=execute_job_cluster_task,
        job_cluster_finished_task=job_cluster_finished_task,
    )


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
    if dag_execution_context.databricks_submission_mode == "task_submission":
        return DatabricksTaskSubmissionEngine(dag_execution_context, config_service)
    return DatabricksJobClusterEngine(dag_execution_context, config_service)


def attach_job_cluster_engine_to_context(
    dag_execution_context: DagExecutionContext,
    config_service: ConfigurationService,
) -> None:
    dag_execution_context.job_cluster_engine = build_job_cluster_engine(
        dag_execution_context, config_service
    )
