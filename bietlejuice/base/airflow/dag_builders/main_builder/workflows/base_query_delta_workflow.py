from typing import List, Tuple
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
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


class BaseQueryDeltaWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates Delta tables from sql files, in a specified Layer.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def __init__(self, dag_args, workflow_args, cluster_args, layer: LayerEnum):
        super().__init__(dag_args, workflow_args, cluster_args)
        self.layer = layer

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
        optimize_delta_tables = self.optimize_delta_table_task_creator.create_task(
            tables
        )
        for table in tables:
            (
                table_first_tasks[table.table_name],
                table_last_tasks[table.table_name],
            ) = self._create_table_tasks(table, optimize_delta_tables)

        self._set_dependencies(
            execute_job_cluster_task,
            table_first_tasks,
            table_last_tasks,
            optimize_delta_tables,
            dummy_terminate_job_cluster_task,
        )

        return dag

    def _get_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the specified layer."""

        query_table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=self.layer.value
        )
        tables = [
            TableAttributes(self.dag_args, self.workflow_args, self.layer, table_name)
            for table_name in query_table_names
        ]
        custom_table_names = self.workflow_args.get("tables_customization", {}).keys()
        for table_name in custom_table_names:
            if table_name in query_table_names:
                continue
            custom_table = TableAttributes(
                self.dag_args, self.workflow_args, self.layer, table_name
            )
            # If this is false, it means that the table in tables_customization does not exist in any way
            if custom_table.has_custom_spark_job:
                tables.append(custom_table)
        return tables

    def _create_table_tasks(self, table: TableAttributes, last_task) -> Tuple:
        """Returns a tuple with the first (Load) and last (Load) tasks of the table."""

        if table.has_custom_spark_job:
            load = self.load_custom_task_creator.create_task(table)
        else:
            load = self.load_query_task_creator.create_task(table)

        if self._check_include_sync_hive_tasks(table):
            register_table = self.register_delta_table_task_creator.create_task(table)
            sync_metadata = self.sync_metadata_task_creator.create_task(
                table, "--bypass-hive"
            )
            (load >> register_table >> sync_metadata >> last_task)
        if self._check_include_data_quality_task(table):
            data_quality = self.data_quality_tests_task_creator.create_task(table)
            load >> data_quality >> last_task
        return load, load

    def _set_dependencies(
        self,
        execute_job_cluster_task,
        table_first_tasks: dict,
        table_last_tasks: dict,
        optimize_delta_tables_task,
        job_cluster_finished_task,
    ) -> None:
        self._set_inner_dependencies(
            table_first_tasks,
            table_last_tasks,
            previous_task_if_no_dependencies=execute_job_cluster_task,
            next_task_if_no_dependents=optimize_delta_tables_task,
        )

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> execute_job_cluster_task

        optimize_delta_tables_task >> job_cluster_finished_task

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_databricks_version="12.2",
        )
        self.load_query_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DELTA
        )
        self.load_custom_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CUSTOM
        )
        self.data_quality_tests_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )
        self.skip_run_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SKIP_RUN
        )
        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.REGISTER_DELTA_TABLE
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
