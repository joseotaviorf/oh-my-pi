from typing import Tuple, List
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
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class RawCustomIngestionWorkflow(BaseWorkflow):
    """
        This workflow is responsible for creating dags for raw ingestions that use custom
        sparkjobs to load data from API's or databases
    """

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)

    def build_dag(self):
        dag = super().dag_instance()

        bucket_config = self.workflow_args.get("bucket_config_name", "datalake_bucket")
        bucket = self.config_service.get_config(bucket_config)
        load_start_date, load_end_date = self._initialize_load_start_and_end_date()
        dag_execution_context = self._get_dag_execution_context(
            dag, bucket, start_date=load_start_date, end_date=load_end_date
        )
        self._initialize_task_creators(dag_execution_context)
        self._create_all_tasks()

        return dag

    def _get_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the clean layer."""

        table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=LayerEnum.CLEAN.value
        )
        return [
            TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.CLEAN, table_name
            )
            for table_name in table_names
        ]

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_databricks_version="12.2",
        )
        self.load_custom_ingestion_raw_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CUSTOM
        )
        self.load_query_clean_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DELTA
        )
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.REGISTER_DELTA_TABLE
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )

    def _create_all_tasks(self) -> None:
        """
        Creates all the tasks for the workflow, and sets their internal dependencies
        """
        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()

        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        clean_delta_tables = self._get_tables()
        optimize_delta_tables_task = self.optimize_delta_table_task_creator.create_task(
            clean_delta_tables
        )
        clean_first_tasks = {}
        clean_last_tasks = {}

        tables_customization = self.workflow_args["tables_customization"]
        for raw_table_name, table_parameters in tables_customization.items():
            clean_table_name = table_parameters.get(
                "clean_table_name", raw_table_name
            ).lower()
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                table_name=raw_table_name, last_task=dummy_terminate_job_cluster_task
            )
            clean_initial_task, clean_final_task = self._create_clean_tasks(
                table_name=clean_table_name,
                table_customization=table_parameters,
                optimize_delta_tables_task=optimize_delta_tables_task,
            )

            execute_job_cluster_task >> raw_initial_task
            raw_final_task >> clean_initial_task
            clean_first_tasks[clean_table_name] = clean_initial_task
            clean_last_tasks[clean_table_name] = clean_final_task
        optimize_delta_tables_task >> dummy_terminate_job_cluster_task
        self._set_inner_dependencies(
            clean_first_tasks,
            clean_last_tasks,
            next_task_if_no_dependents=optimize_delta_tables_task,
        )

    def _create_raw_tasks(self, table_name: str, last_task) -> Tuple:
        """
        Creates raw tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        raw_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.RAW,
            table_name.lower(),  # The table name must be lower case for most of the tasks, to avoid problems with Hive
        )

        load_raw_task = self.load_custom_ingestion_raw_task_creator.create_task(
            TableAttributes.from_attributes(
                raw_table_attributes,
                table_name=table_name,  # The exception is the load task, which must have the original table name, for it to be found in the source
            )
        )

        if self._check_include_sync_hive_tasks(raw_table_attributes):

            if self._check_include_propagate_metadata_task(raw_table_attributes):
                sync_metadata = self.sync_metadata_task_creator.create_task(
                    raw_table_attributes
                )
            else:
                sync_metadata = self.sync_metadata_task_creator.create_task(
                    raw_table_attributes, "--bypass-propagate"
                )

            (load_raw_task >> sync_metadata >> last_task)

        if self._check_include_data_quality_task(raw_table_attributes):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes
            )
            (load_raw_task >> data_quality_tests_raw_task >> last_task)

        return load_raw_task, load_raw_task

    def _create_clean_tasks(
        self, table_name: str, table_customization: dict, optimize_delta_tables_task
    ) -> Tuple:
        """
        Creates clean tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        clean_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.CLEAN,
            table_name,
            table_customization,
        )

        load_clean_task = self.load_query_clean_task_creator.create_task(
            clean_table_attributes
        )

        if self._check_include_sync_hive_tasks(clean_table_attributes):
            register_table = self.register_delta_table_task_creator.create_task(
                clean_table_attributes
            )
            sync_metadata = self.sync_metadata_task_creator.create_task(
                clean_table_attributes, "--bypass-hive"
            )
            (
                load_clean_task
                >> register_table
                >> sync_metadata
                >> optimize_delta_tables_task
            )
        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            load_clean_task >> data_quality >> optimize_delta_tables_task
        return load_clean_task, load_clean_task
