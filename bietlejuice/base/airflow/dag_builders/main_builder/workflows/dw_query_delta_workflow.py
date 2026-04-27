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
from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_job_cluster_finished_work_prerequisites,
    get_job_cluster_completion_sink,
)


class DwQueryDeltaWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates Delta tables from sql files, in the DW Layer.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def build_dag(self):
        dag = self.dag_instance()
        bucket_config = self.workflow_args.get("bucket_config_name", "dw_bucket")
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
            ) = self._create_dw_tasks(table, optimize_delta_tables)

        self._set_dependencies(
            dag_execution_context,
            execute_job_cluster_task,
            table_first_tasks,
            table_last_tasks,
            optimize_delta_tables,
            dummy_terminate_job_cluster_task,
        )

        DatasetAdder.attach_reprocessing_guard(
            execute_job_cluster_task, dag_execution_context
        )

        return dag

    def _get_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the dw layer.

        Tables are discovered from two sources:
        1. SQL files in queries/dw/ directory
        2. Entries in tables_customization with load_spark_job (custom Spark jobs)
        """
        query_table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=LayerEnum.DW.value
        )
        tables = [
            TableAttributes(self.dag_args, self.workflow_args, LayerEnum.DW, table_name)
            for table_name in sorted(query_table_names)
        ]
        custom_table_names = self.workflow_args.get("tables_customization", {}).keys()
        for table_name in custom_table_names:
            if table_name in query_table_names:
                continue
            custom_table = TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.DW, table_name
            )
            if custom_table.has_custom_spark_job:
                tables.append(custom_table)
        return tables

    def _create_dw_tasks(self, table: TableAttributes, last_task_after_groups) -> Tuple:
        """Returns a tuple with the first (Load) and last (Load or add default row) tasks of the table."""

        if table.has_custom_spark_job:
            load = self.load_custom_task_creator.create_task(table)
        else:
            load = self.load_dw_task_creator.create_task(table)
        last_task_in_group = load
        if self._check_include_add_default_row_task(table):
            add_default_row = self.add_default_row_task_creator.create_task(table)
            load >> add_default_row
            last_task_in_group = add_default_row
        if self._check_include_sync_hive_tasks(table):
            register_table = self.register_delta_table_task_creator.create_task(table)
            sync_metadata = self.sync_metadata_task_creator.create_task(
                table, "--bypass-hive"
            )
            (load >> register_table >> sync_metadata >> last_task_after_groups)
        if self._check_include_data_quality_task(table):
            data_quality = self.data_quality_tests_task_creator.create_task(table)
            load >> data_quality >> last_task_after_groups
        return load, last_task_in_group

    def _check_include_add_default_row_task(self, table: TableAttributes) -> bool:
        return (
            table.layer == LayerEnum.DW
            and table.table_name.startswith("dim_")
            and table.extraction_type == "full"
        )

    def _set_dependencies(
        self,
        dag_execution_context: DagExecutionContext,
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

        cluster_completion_sink = get_job_cluster_completion_sink(
            dag_execution_context,
            execute_job_cluster_task,
            job_cluster_finished_task,
            None,
        )
        optimize_delta_tables_task >> cluster_completion_sink
        attach_emr_job_cluster_finished_work_prerequisites(
            dag_execution_context,
            job_cluster_finished_task,
            cluster_completion_sink=cluster_completion_sink,
        )

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_cluster_runtime_version="12.2",
        )
        self.load_dw_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DELTA
        )
        self.load_custom_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CUSTOM, storage_format=StorageFormatEnum.DELTA
        )
        self.add_default_row_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.ADD_DEFAULT_ROW, is_delta=True
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
        self.dummy_job_cluster_finished_task_creator = (
            task_creator_factory.get_task_creator(TaskEnum.DUMMY_JOB_CLUSTER_FINISHED)
        )
