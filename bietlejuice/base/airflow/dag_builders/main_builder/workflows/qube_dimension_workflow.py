"""
QUBE Dimension Workflow

Builds QUBE dimension tables from YAML specs.
"""

from typing import List
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


class QubeDimensionWorkflow(BaseWorkflow):
    """
    Workflow for building QUBE dimension tables.

    This workflow reads dimension specs from the workflow_args and creates
    tasks to build each dimension table.
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

    def _get_dimension_specs(self) -> List[TableAttributes]:
        """Returns table attributes for all dimension specs."""
        qube_specs = self.workflow_args.get("qube_specs", {})
        if not qube_specs:
            return []

        # qube_specs now contains the spec directly (flattened)
        # Get the spec name from the spec itself
        spec_name = qube_specs.get("name", "")
        if not spec_name:
            # Fallback: try to get from folder_name or dag name
            spec_name = self.dag_args.get("folder_name", "").replace("dimensions_", "")

        return [
            TableAttributes(
                self.dag_args,
                self.workflow_args,
                LayerEnum.QUBE,
                spec_name,
                table_customization=qube_specs,
            )
        ]

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

        dimension_specs = self._get_dimension_specs()

        # Create tasks for each dimension spec
        for table_attributes in dimension_specs:
            dimension_task = self.build_qube_dimension_task_creator.create_task(
                table_attributes
            )
            execute_job_cluster_task >> dimension_task

            # Add Trino registration if has_hive_sync is enabled
            if self._check_include_sync_hive_tasks(table_attributes):
                register_task = self.register_delta_table_task_creator.create_task(
                    table_attributes
                )
                dimension_task >> register_task >> dummy_terminate_job_cluster_task
            else:
                dimension_task >> dummy_terminate_job_cluster_task

    def _check_include_sync_hive_tasks(self, table_attributes: TableAttributes) -> bool:
        """
        Checks if Trino registration task should be added into the workflow.
        """
        default_has_hive_sync = self.workflow_args.get("has_hive_sync", True)
        return table_attributes.table_customization.get(
            "has_hive_sync", default_has_hive_sync
        )
