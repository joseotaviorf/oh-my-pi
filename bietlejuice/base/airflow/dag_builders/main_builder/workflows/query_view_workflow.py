from typing import List, Tuple
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
    TaskEnum,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class QueryViewWorkflow(BaseWorkflow):
    """
    Workflow for creating views on both Databricks and Trino using query_view type.
    This workflow creates non-materialized views that are automatically overwritten on every execution.

    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def build_dag(self):
        dag = self.dag_instance()
        bucket_config = self.workflow_args.get("bucket_config_name", "datalake_bucket")
        bucket = self.config_service.get_config(bucket_config)
        dag_execution_context = self._get_dag_execution_context(dag, bucket)
        self._initialize_task_creators(dag_execution_context)

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        table_first_tasks = {}
        table_last_tasks = {}
        tables = self._get_tables()

        for table in tables:
            (
                table_first_tasks[table.table_name],
                table_last_tasks[table.table_name],
            ) = self._create_query_view_tasks(table, dummy_terminate_job_cluster_task)

        self._set_dependencies(
            execute_job_cluster_task,
            table_first_tasks,
            table_last_tasks,
            dummy_terminate_job_cluster_task,
        )

        DatasetAdder.attach_reprocessing_guard(
            execute_job_cluster_task, dag_execution_context
        )

        return dag

    def _get_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the layer."""
        layer = LayerEnum(self.workflow_args["layer"])

        query_table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=layer.value
        )
        tables = [
            TableAttributes(self.dag_args, self.workflow_args, layer, table_name)
            for table_name in query_table_names
        ]

        custom_table_names = self.workflow_args.get("tables_customization", {}).keys()
        for table_name in custom_table_names:
            if table_name in query_table_names:
                continue

            custom_table = TableAttributes(
                self.dag_args, self.workflow_args, layer, table_name
            )

            tables.append(custom_table)

        return tables

    def _create_query_view_tasks(self, table: TableAttributes, last_task) -> Tuple:
        """Returns a tuple with the first (CreateQueryView) and last (CreateQueryView) tasks of the table."""

        create_view_task = self.create_query_view_task_creator.create_task(table)

        last_task_in_chain = create_view_task

        if self._check_include_sync_hive_tasks(table):
            sync_metadata = self.sync_metadata_task_creator.create_task(table)
            last_task_in_chain >> sync_metadata
            last_task_in_chain = sync_metadata

        if self._check_include_data_quality_task(table):
            data_quality = self.data_quality_tests_task_creator.create_task(table)
            last_task_in_chain >> data_quality
            last_task_in_chain = data_quality

        last_task_in_chain >> last_task

        return create_view_task, create_view_task

    def _set_dependencies(
        self,
        execute_job_cluster_task,
        table_first_tasks: dict,
        table_last_tasks: dict,
        job_cluster_finished_task,
    ) -> None:
        """Set task dependencies including inner dependencies if configured."""

        self._set_inner_dependencies(
            table_first_tasks,
            table_last_tasks,
            previous_task_if_no_dependencies=execute_job_cluster_task,
            next_task_if_no_dependents=job_cluster_finished_task,
        )

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> execute_job_cluster_task

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        """Initialize all task creators used by this workflow."""
        task_creator_factory = TaskCreatorFactory(dag_execution_context)

        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER, self.config_service
        )
        self.create_query_view_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.CREATE_QUERY_VIEW
        )
        self.data_quality_tests_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )
        self.skip_run_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SKIP_RUN
        )
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
