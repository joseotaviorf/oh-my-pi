from typing import List, Tuple, override

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_job_cluster_finished_work_prerequisites,
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


class CoreModelWorkflow(BaseWorkflow):
    """
    # This workflow builds DAGs for core model tables, which are the single source of truth
    # for critical business entities (e.g., visits, contracts, offers, properties).
    # Core models are business-critical, compliance-sensitive, and power all downstream analytics,
    # machine learning, and business intelligence. Data quality and performance in these workflows
    # directly impact business decisions and customer experience.
    """

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

    def _get_core_model_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the transactional layer."""
        return [
            TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.CORE, table_name
            )
            for table_name in self.workflow_args["tables_customization"]
        ]

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_cluster_runtime_version="12.2",
        )
        self.load_core_model_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CORE_MODEL
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )
        self.skip_run_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SKIP_RUN
        )
        self.dummy_job_cluster_finished_task_creator = (
            task_creator_factory.get_task_creator(TaskEnum.DUMMY_JOB_CLUSTER_FINISHED)
        )
        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.REGISTER_DELTA_TABLE
        )
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )

    def _create_all_tasks(self) -> None:
        """
        Creates all the tasks for the workflow, and sets their internal dependencies
        """
        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> execute_job_cluster_task

        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        cluster_completion_sink = get_job_cluster_completion_sink(
            self.dag_execution_context,
            execute_job_cluster_task,
            dummy_terminate_job_cluster_task,
            None,
        )
        core_delta_tables = self._get_core_model_tables()
        optimize_delta_tables_task = self.optimize_delta_table_task_creator.create_task(
            core_delta_tables
        )

        core_model_first_tasks = {}
        core_model_last_tasks = {}

        # Create core model tasks for each table
        for table_name, table_parameters in self.workflow_args[
            "tables_customization"
        ].items():
            core_model_initial_task, core_model_final_task = (
                self._create_core_model_tasks(
                    table_name=table_name, last_task=optimize_delta_tables_task
                )
            )

            core_model_first_tasks[table_name.lower()] = core_model_initial_task
            core_model_last_tasks[table_name.lower()] = core_model_final_task

        # Set dependencies between core model tasks based on inner_dependencies
        self._set_inner_dependencies(
            table_first_tasks=core_model_first_tasks,
            table_last_tasks=core_model_last_tasks,
            previous_task_if_no_dependencies=execute_job_cluster_task,
            next_task_if_no_dependents=optimize_delta_tables_task,
            inner_dependencies_key="inner_dependencies",
        )

        optimize_delta_tables_task >> cluster_completion_sink
        attach_emr_job_cluster_finished_work_prerequisites(
            self.dag_execution_context,
            dummy_terminate_job_cluster_task,
            cluster_completion_sink=cluster_completion_sink,
        )

    @override
    def _check_include_sync_hive_tasks(self, table_attributes: TableAttributes) -> bool:
        """
        Checks if sync hive structure task should be added into the workflow.
        """
        default_has_hive_sync = self.workflow_args.get("has_hive_sync", False)
        return table_attributes.table_customization.get(
            "has_hive_sync", default_has_hive_sync
        )

    def _create_core_model_tasks(self, table_name: str, last_task) -> Tuple:
        """
        Creates core model tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        core_model_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.CORE,
            table_name.lower(),  # The table name must be lower case for most of the tasks, to avoid problems with Hive
        )

        load_core_model_task = self.load_core_model_task_creator.create_task(
            core_model_table_attributes
        )

        current_last_task = load_core_model_task

        if self._check_include_sync_hive_tasks(core_model_table_attributes):
            register_table = self.register_delta_table_task_creator.create_task(
                core_model_table_attributes
            )
            sync_metadata = self.sync_metadata_task_creator.create_task(
                core_model_table_attributes, "--bypass-hive"
            )
            load_core_model_task >> register_table >> sync_metadata
            current_last_task = sync_metadata

        if self._check_include_data_quality_task(core_model_table_attributes):
            data_quality = self.data_quality_task_creator.create_task(
                core_model_table_attributes
            )
            current_last_task >> data_quality
            current_last_task = data_quality

        return load_core_model_task, current_last_task
