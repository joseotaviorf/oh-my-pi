from typing import List, Tuple

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow import (
    BaseQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.cdf_to_datazord_workflow import (
    create_cdf_task_if_configured,
    get_datazord_config,
    initialize_cdf_task_creator,
    wire_task_to_sink,
)
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_job_cluster_finished_work_prerequisites,
    attach_emr_terminate_cluster_work_prerequisites,
    get_job_cluster_completion_sink,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
)


class BaseQueryDeltaDatazordWorkflow(BaseQueryDeltaWorkflow):
    """query_delta workflow that streams Delta CDF to Datazord after the table load.

    CDF runs after ``load`` and before register/sync, data quality, optimize, etc.
    Opt-in at the DAG level via ``workflow.type: query_delta_datazord``.
    ``datazord_config`` is required.
    """

    def _create_all_tasks_for_cluster(
        self,
        cluster_tables: List[TableAttributes],
        execute_job_cluster_local_id: int,
        dummy_terminate_job_cluster_task,
        dag_execution_context: DagExecutionContext,
    ):
        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task(
            execute_job_cluster_local_id if execute_job_cluster_local_id > 1 else None
        )

        if not self.is_validation:
            optimize_delta_tables = self.optimize_delta_table_task_creator.create_task(
                cluster_tables,
                optimize_delta_table_local_id=(
                    execute_job_cluster_local_id
                    if execute_job_cluster_local_id > 1
                    else None
                ),
            )
        else:
            optimize_delta_tables = None

        table_first_tasks = {}
        table_last_tasks = {}

        for table in cluster_tables:
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
            dag_execution_context,
            execute_job_cluster_local_id,
        )

        return execute_job_cluster_task

    def _set_dependencies(
        self,
        execute_job_cluster_task,
        table_first_tasks: dict,
        table_last_tasks: dict,
        optimize_delta_tables_task,
        job_cluster_finished_task,
        dag_execution_context: DagExecutionContext,
        execute_job_cluster_local_id: int,
    ) -> None:
        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> execute_job_cluster_task

        cluster_completion_sink = get_job_cluster_completion_sink(
            dag_execution_context,
            execute_job_cluster_task,
            job_cluster_finished_task,
            execute_job_cluster_local_id,
        )

        if optimize_delta_tables_task is not None:
            self._set_inner_dependencies(
                table_first_tasks,
                table_last_tasks,
                previous_task_if_no_dependencies=execute_job_cluster_task,
                next_task_if_no_dependents=optimize_delta_tables_task,
            )
            wire_task_to_sink(optimize_delta_tables_task, cluster_completion_sink)
        else:
            self._set_inner_dependencies(
                table_first_tasks,
                table_last_tasks,
                previous_task_if_no_dependencies=execute_job_cluster_task,
                next_task_if_no_dependents=cluster_completion_sink,
            )

        attach_emr_job_cluster_finished_work_prerequisites(
            dag_execution_context,
            job_cluster_finished_task,
            cluster_completion_sink=cluster_completion_sink,
        )
        attach_emr_terminate_cluster_work_prerequisites(
            dag_execution_context,
            cluster_completion_sink,
            execute_job_cluster_task=execute_job_cluster_task,
        )

    def _create_table_tasks(self, table: TableAttributes, last_task) -> Tuple:
        if table.has_custom_spark_job:
            load = self.load_custom_task_creator.create_task(table)
        else:
            load = self.load_query_task_creator.create_task(table)

        post_load = load
        datazord_config = get_datazord_config(self.workflow_args)
        if (
            not self.is_validation
            and datazord_config
            and table.table_name == datazord_config["table"]
        ):
            load_cdf_to_datazord_task = create_cdf_task_if_configured(
                self.load_cdf_to_datazord_task_creator,
                self.dag_args,
                self.workflow_args,
                self.layer,
            )
            if load_cdf_to_datazord_task is not None:
                load >> load_cdf_to_datazord_task
                post_load = load_cdf_to_datazord_task

        if self._check_include_sync_hive_tasks(table):
            register_table = self.register_delta_table_task_creator.create_task(table)
            sync_metadata = self.sync_metadata_task_creator.create_task(
                table, "--bypass-hive"
            )
            post_load >> register_table >> sync_metadata >> last_task
        if self._check_include_data_quality_task(table):
            data_quality = self.data_quality_tests_task_creator.create_task(table)
            post_load >> data_quality
            if last_task is not None:
                data_quality >> last_task
        if self._check_include_profiling_task(table):
            profiling = self.profiling_task_creator.create_task(table)
            post_load >> profiling
            if last_task is not None:
                profiling >> last_task
        return load, post_load

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        super()._initialize_task_creators(dag_execution_context)
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.load_cdf_to_datazord_task_creator = initialize_cdf_task_creator(
            task_creator_factory, self.config_service
        )
