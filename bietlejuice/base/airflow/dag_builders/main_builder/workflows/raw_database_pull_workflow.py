import math
from typing import Tuple
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


class RawDatabasePullWorkflow(BaseWorkflow):
    MAX_TABLES_PER_CLUSTER = 20

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)

    def build_dag(self):
        dag = super().dag_instance()

        bucket = self.config_service.get_config("datalake_bucket")
        load_start_date, load_end_date = self._initialize_load_start_and_end_date()
        dag_execution_context = self._get_dag_execution_context(
            dag, bucket, start_date=load_start_date, end_date=load_end_date
        )
        self._initialize_task_creators(dag_execution_context)

        dag_final_tasks = self._set_dag_final_tasks()

        tables_customization = self.workflow_args["tables_customization"]

        n_clusters = len(tables_customization) // self.MAX_TABLES_PER_CLUSTER + 1
        tables_per_cluster = math.ceil(len(tables_customization) / n_clusters)
        n_tables_so_far = 0
        execute_job_cluster_local_id = 1

        for raw_table_name, table_parameters in tables_customization.items():
            if n_tables_so_far % tables_per_cluster == 0:
                execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task(
                    execute_job_cluster_local_id=execute_job_cluster_local_id
                )
                execute_job_cluster_local_id += 1
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                table_name=raw_table_name, dag_final_tasks=dag_final_tasks
            )
            clean_initial_task, clean_final_task = self._create_clean_tasks(
                table_name=table_parameters.get(
                    "clean_table_name", raw_table_name
                ).lower(),
                table_customization=table_parameters,
                dag_final_tasks=dag_final_tasks,
            )
            execute_job_cluster_task >> raw_initial_task
            raw_final_task >> clean_initial_task
            clean_final_task >> dag_final_tasks
            n_tables_so_far += 1

        return dag

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER, self.config_service
        )
        self.load_database_pull_raw_task_creator = task_creator_factory.get_database_task_creator(
            self.workflow_args["database_type"]
        )
        self.load_query_clean_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_QUERY
        )
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )
        self.generate_database_table_metrics_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.GENERATE_DATABASE_TABLE_METRICS
        )

    def _create_raw_tasks(self, table_name: str, dag_final_tasks) -> Tuple:
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

        load_raw_task = self.load_database_pull_raw_task_creator.create_task(
            TableAttributes.from_attributes(
                raw_table_attributes,
                table_name=table_name,  # The exception is the load task, which must have the original table name, for it to be found in the source database
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

            (load_raw_task >> sync_metadata >> dag_final_tasks)

        if self._check_include_data_quality_task(raw_table_attributes):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes
            )
            (load_raw_task >> data_quality_tests_raw_task >> dag_final_tasks)

        return load_raw_task, load_raw_task

    def _create_clean_tasks(
        self, table_name: str, table_customization: dict, dag_final_tasks
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
        last_clean_task = load_clean_task

        if self._check_include_sync_hive_tasks(clean_table_attributes):
            sync_metadata = self.sync_metadata_task_creator.create_task(
                clean_table_attributes
            )

            last_clean_task = sync_metadata

            (load_clean_task >> sync_metadata >> dag_final_tasks)

        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality_tests_clean_task = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            (load_clean_task >> data_quality_tests_clean_task >> dag_final_tasks)

        return load_clean_task, last_clean_task

    def _set_dag_final_tasks(self):
        """
        The final task of the DAG will either be the dummy_terminate_job_cluster_task, or the get_table_metrics_task.
        This method creates the metrics task if it should be included in the workflow, and sets the dependencies. Otherwise,
        it simply returns the dummy_terminate_job_cluster_task.
        """
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        if self._check_include_get_table_metrics_task(
            self.workflow_args["tables_customization"]
        ):
            first_metrics_task, last_metrics_task = self._create_generate_metrics_task_group(
                self.generate_database_table_metrics_task_creator,
                self.sync_metadata_task_creator,
            )
            last_metrics_task >> dummy_terminate_job_cluster_task
            return first_metrics_task
        else:
            return dummy_terminate_job_cluster_task
