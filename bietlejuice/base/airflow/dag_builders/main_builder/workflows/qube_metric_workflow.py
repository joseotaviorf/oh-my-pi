"""
QUBE Metric Workflow

Builds QUBE metric tables from YAML specs, automatically handling
dependencies on dimensions and measures.
"""

from airflow.models import DAG
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum

# Add project root to path for qube imports
# sys.path.append(os.path.join(os.path.dirname(__file__), "../../../../../../.."))
from bietlejuice.qube.jobs.common.specs_loader import load_spec


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

        return DagExecutionContext(
            dag,
            self.env,
            bucket,
            base_spark_jobs_path,
            self.dag_args,
            self.workflow_args,
            self.cluster_args,
            **kwargs,
        )

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
            minimum_databricks_version="12.2",
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

        # Load metric spec to get dependencies
        metric_spec = self._load_metric_spec()

        # For dependencies, we still need to load dimension/measure specs from files
        # since they're in separate declaration files. We'll load from qube/specs.
        # Create dimension tasks
        dim_tasks = {}
        for dim_spec in metric_spec.get("dimensions", []):
            dim_name = dim_spec["name"]
            # Load dimension spec from file for dependency tasks
            try:
                dim_full_spec = load_spec(
                    f"dags/qube/dimensions_{dim_name}/dimensions_{dim_name}_declaration.yaml"
                )
            except FileNotFoundError:
                # Fallback: try dags/qube/specs

                dim_full_spec = load_spec(f"qube/specs/dimensions/{dim_name}.yaml")

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
            # Load measure spec from file for dependency tasks
            try:
                meas_full_spec = load_spec(f"dags/qube/{meas_name}.yaml")
            except FileNotFoundError:
                meas_full_spec = load_spec(f"qube/specs/measures/{meas_name}.yaml")

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
            metric_task >> register_task >> dummy_terminate_job_cluster_task
        else:
            metric_task >> dummy_terminate_job_cluster_task

    def _check_include_sync_hive_tasks(self, table_attributes: TableAttributes) -> bool:
        """
        Checks if Trino registration task should be added into the workflow.
        """
        default_has_hive_sync = self.workflow_args.get("has_hive_sync", True)
        return table_attributes.table_customization.get(
            "has_hive_sync", default_has_hive_sync
        )
