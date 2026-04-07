"""
QUBE Metric Workflow

Builds QUBE metric tables from YAML specs, automatically handling
dependencies on dimensions and measures.
"""

from pathlib import Path

import yaml
from airflow.models import DAG
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_job_cluster_engine_to_context,
    get_job_cluster_completion_sink,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum

# Repo root (= /usr/local/airflow/ in Airflow container, repo root locally).
# parents[6]: workflows -> main_builder -> dag_builders -> airflow -> base -> bietlejuice -> repo_root
_DAGS_ROOT = Path(__file__).resolve().parents[6]


def _find_qube_declaration(entity_type: str, spec_name: str) -> dict:
    """
    Find a qube declaration file by scanning entity_type directories for
    a matching workflow.qube_specs.name value, and return the qube_specs
    content dict directly.

    Scanning is necessary because declaration folder names don't always
    match qube_specs.name (e.g. folder measures_visit_unique has
    qube_specs.name=unique_visits).

    The qube_specs content (entity, name, source, logic, …) is returned
    directly so callers can pass it straight to task creators as the job
    spec — avoiding the DAG-builder wrapper (dag/workflow/cluster keys)
    that build_dimension / build_measure / build_metric do not expect.

    Args:
        entity_type: "dimensions" or "measures"
        spec_name: The qube_specs.name value to search for

    Returns:
        The workflow.qube_specs dict from the matching declaration file

    Raises:
        FileNotFoundError: If no matching declaration is found
    """
    qube_dir = _DAGS_ROOT / "dags" / "qube"
    for subdir in sorted(qube_dir.iterdir()):
        if not subdir.is_dir() or not subdir.name.startswith(f"{entity_type}_"):
            continue
        decl_file = subdir / f"{subdir.name}_declaration.yml"
        if not decl_file.exists():
            continue
        with open(decl_file) as f:
            content = yaml.safe_load(f)
        qube_specs = content.get("workflow", {}).get("qube_specs", {})
        if qube_specs.get("name") == spec_name:
            return qube_specs
    raise FileNotFoundError(
        f"No {entity_type} declaration found with qube_specs.name='{spec_name}' in {qube_dir}"
    )


class QubeMetricWorkflow(BaseWorkflow):
    """
    Workflow for building QUBE metric tables.

    This workflow reads a metric spec and automatically creates tasks for
    all required dimensions and measures, then the metric itself, with
    proper dependencies.
    """

    def _get_dag_execution_context(
        self, dag: DAG, bucket: str, **kwargs
    ) -> DagExecutionContext:
        """Override to set QUBE-specific Spark jobs path."""
        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        # Point to bietlejuice/qube/jobs/ instead of spark_jobs/base/
        base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/qube/jobs/"

        ctx = DagExecutionContext(
            dag,
            self.env,
            bucket,
            base_spark_jobs_path,
            self.dag_args,
            self.workflow_args,
            self.cluster_args,
            **kwargs,
        )
        attach_job_cluster_engine_to_context(ctx, self.config_service)
        return ctx

    def build_dag(self):
        dag = super().dag_instance()

        bucket_config = self.workflow_args.get("bucket_config_name", "datalake_bucket")
        bucket = self.config_service.get_config(bucket_config)
        load_start_date, load_end_date = self._initialize_load_start_and_end_date()
        self.dag_execution_context = self._get_dag_execution_context(
            dag, bucket, load_start_date=load_start_date, load_end_date=load_end_date
        )
        self._initialize_task_creators(self.dag_execution_context)
        self._create_all_tasks()

        return dag

    def _load_metric_spec(self):
        """Loads the metric spec from qube_specs."""
        qube_specs = self.workflow_args.get("qube_specs", {})
        if not qube_specs:
            raise ValueError("Metric spec content is required in qube_specs")
        return qube_specs

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_cluster_runtime_version="12.2",
        )
        self.build_qube_dimension_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.BUILD_QUBE_DIMENSION
        )
        self.build_qube_measure_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.BUILD_QUBE_MEASURE
        )
        self.build_qube_metric_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.BUILD_QUBE_METRIC
        )
        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.QUBE_REGISTER_DELTA_TABLE
        )
        self.dummy_job_cluster_finished_task_creator = (
            task_creator_factory.get_task_creator(TaskEnum.DUMMY_JOB_CLUSTER_FINISHED)
        )

    def _create_all_tasks(self) -> None:
        """Creates all tasks for the workflow and sets dependencies."""
        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        cluster_completion_sink = get_job_cluster_completion_sink(
            self.dag_execution_context,
            execute_job_cluster_task,
            dummy_terminate_job_cluster_task,
            None,
        )

        # Load metric spec to get dependencies
        metric_spec = self._load_metric_spec()

        # Create dimension tasks
        # _find_qube_declaration returns the qube_specs dict directly (entity,
        # name, source, logic, …) — not the full DAG-builder declaration — so
        # the Databricks job receives the flat spec it expects.
        dim_tasks = {}
        for dim_spec in metric_spec.get("dimensions", []):
            dim_name = dim_spec["name"]
            dim_full_spec = _find_qube_declaration("dimensions", dim_name)

            table_attributes = TableAttributes(
                self.dag_args,
                self.workflow_args,
                LayerEnum.QUBE,
                dim_name,
                table_customization=dim_full_spec,
            )
            dim_task = self.build_qube_dimension_task_creator.create_task(
                table_attributes
            )
            dim_tasks[dim_name] = dim_task
            execute_job_cluster_task >> dim_task

        # Create measure tasks
        meas_tasks = {}
        for meas_spec in metric_spec.get("measures", []):
            meas_name = meas_spec["name"]
            meas_full_spec = _find_qube_declaration("measures", meas_name)

            table_attributes = TableAttributes(
                self.dag_args,
                self.workflow_args,
                LayerEnum.QUBE,
                meas_name,
                table_customization=meas_full_spec,
            )
            meas_task = self.build_qube_measure_task_creator.create_task(
                table_attributes
            )
            meas_tasks[meas_name] = meas_task
            execute_job_cluster_task >> meas_task

        # Create metric task (depends on all dimensions and measures)
        # Metric spec is now inline in workflow_args
        metric_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.QUBE,
            metric_spec.get("name", "metric"),
            table_customization=metric_spec,
        )
        metric_task = self.build_qube_metric_task_creator.create_task(
            metric_table_attributes
        )

        # Set dependencies: all dimensions and measures must complete before metric
        for dim_task in dim_tasks.values():
            dim_task >> metric_task
        for meas_task in meas_tasks.values():
            meas_task >> metric_task

        # Add Trino registration if has_hive_sync is enabled
        if self._check_include_sync_hive_tasks(metric_table_attributes):
            register_task = self.register_delta_table_task_creator.create_task(
                metric_table_attributes
            )
            metric_task >> register_task >> cluster_completion_sink
        else:
            metric_task >> cluster_completion_sink

    def _check_include_sync_hive_tasks(self, table_attributes: TableAttributes) -> bool:
        """
        Checks if Trino registration task should be added into the workflow.
        """
        default_has_hive_sync = self.workflow_args.get("has_hive_sync", True)
        return table_attributes.table_customization.get(
            "has_hive_sync", default_has_hive_sync
        )
