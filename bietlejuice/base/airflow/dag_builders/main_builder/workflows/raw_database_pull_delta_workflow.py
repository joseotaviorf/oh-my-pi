import math
from typing import List, Tuple
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


class RawDatabasePullDeltaWorkflow(BaseWorkflow):
    MAX_TABLES_PER_CLUSTER = 19

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)

    def build_dag(self):
        dag = super().dag_instance()

        bucket_config = self.workflow_args.get("bucket_config_name", "datalake_bucket")
        bucket = self.config_service.get_config(bucket_config)
        load_start_date, load_end_date = self._initialize_load_start_and_end_date()
        dag_execution_context = self._get_dag_execution_context(
            dag, bucket, load_start_date=load_start_date, load_end_date=load_end_date
        )
        self._initialize_task_creators(dag_execution_context)

        tables_customization = self.workflow_args["tables_customization"]

        all_raw_tables = self._get_raw_tables()
        all_clean_tables = self._get_clean_tables(all_raw_tables)
        self._create_all_tasks(all_raw_tables, all_clean_tables, tables_customization)

        return dag

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_databricks_version="12.2",
        )
        self.load_database_pull_raw_task_creator = task_creator_factory.get_database_task_creator(
            self.workflow_args["database_type"]
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
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )
        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.REGISTER_DELTA_TABLE
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.generate_database_table_metrics_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.GENERATE_DATABASE_TABLE_METRICS
        )

    def _get_raw_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the raw layer from tables_customization."""
        return [
            TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.RAW, table_name
            )
            for table_name in self.workflow_args["tables_customization"]
        ]

    def _get_clean_tables(
        self, raw_tables: List[TableAttributes]
    ) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the clean layer, by copying from the raw layer."""
        return [
            TableAttributes.from_attributes(
                table,
                layer=LayerEnum.CLEAN,
                table_name=table.table_customization.get(
                    "clean_table_name", table.table_name
                ).lower(),
            )
            for table in raw_tables
        ]

    def _create_all_tasks(
        self,
        all_raw_tables: List[TableAttributes],
        all_clean_tables: List[TableAttributes],
        tables_customization: dict,
    ) -> None:
        """Creates all the tasks for the DAG and set their dependencies"""
        cluster_raw_tables = []
        cluster_clean_tables = []
        execute_job_cluster_local_id = 1
        n_clusters = len(tables_customization) // self.MAX_TABLES_PER_CLUSTER + 1
        tables_per_cluster = math.ceil(len(tables_customization) / n_clusters)
        n_tables_so_far = 0

        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        for raw_table, clean_table in zip(all_raw_tables, all_clean_tables):
            if n_tables_so_far != 0 and n_tables_so_far % tables_per_cluster == 0:
                self._create_all_tasks_for_cluster(
                    cluster_raw_tables,
                    cluster_clean_tables,
                    execute_job_cluster_local_id,
                    dummy_terminate_job_cluster_task,
                )
                cluster_raw_tables = []
                cluster_clean_tables = []
                execute_job_cluster_local_id += 1
            cluster_raw_tables.append(raw_table)
            cluster_clean_tables.append(clean_table)
            n_tables_so_far += 1

        if len(cluster_raw_tables) > 0:
            self._create_all_tasks_for_cluster(
                cluster_raw_tables,
                cluster_clean_tables,
                execute_job_cluster_local_id,
                dummy_terminate_job_cluster_task,
            )

    def _create_all_tasks_for_cluster(
        self,
        cluster_raw_tables: List[TableAttributes],
        cluster_clean_tables: List[TableAttributes],
        execute_job_cluster_local_id: int,
        dummy_terminate_job_cluster_task,
    ) -> None:
        """Creates all the tasks from a cluster for the workflow and sets their dependencies."""

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task(
            execute_job_cluster_local_id
        )
        optimize_clean_task = self.optimize_delta_table_task_creator.create_task(
            table_attributes=cluster_clean_tables,
            optimize_delta_table_local_id=execute_job_cluster_local_id,
        )
        dag_final_tasks = self._set_dag_final_tasks(
            execute_job_cluster_local_id, dummy_terminate_job_cluster_task
        )

        for raw_table, clean_table in zip(cluster_raw_tables, cluster_clean_tables):
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                raw_table, dag_final_tasks=dag_final_tasks
            )
            clean_initial_task, clean_final_task = self._create_clean_tasks(
                clean_table, optimize_clean_task, dag_final_tasks=dag_final_tasks
            )
            execute_job_cluster_task >> raw_initial_task
            raw_final_task >> clean_initial_task
            clean_final_task >> dag_final_tasks

        optimize_clean_task >> dag_final_tasks

    def _create_raw_tasks(
        self, raw_table_attributes: TableAttributes, dag_final_tasks
    ) -> Tuple:
        """
        Creates raw tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """

        # Since we are ingesting directly from Database, the table name is case sensitive.
        load_raw_task = self.load_database_pull_raw_task_creator.create_task(
            raw_table_attributes
        )

        # Since we always save the table name as lower case in datalake, we must change it.
        raw_table_attributes = TableAttributes.from_attributes(
            raw_table_attributes, table_name=raw_table_attributes.table_name.lower()
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
        self,
        clean_table_attributes: TableAttributes,
        optimize_clean_task: dict,
        dag_final_tasks,
    ) -> Tuple:
        """
        Creates clean tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        load_clean_task = self.load_query_clean_task_creator.create_task(
            clean_table_attributes
        )
        load_clean_task >> optimize_clean_task
        last_clean_task = load_clean_task

        if self._check_include_sync_hive_tasks(clean_table_attributes):
            register_table = self.register_delta_table_task_creator.create_task(
                clean_table_attributes
            )
            sync_metadata = self.sync_metadata_task_creator.create_task(
                clean_table_attributes, "--bypass-hive"
            )

            last_clean_task = sync_metadata

            (load_clean_task >> register_table >> sync_metadata)

        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality_tests_clean_task = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            (load_clean_task >> data_quality_tests_clean_task >> dag_final_tasks)

        return load_clean_task, last_clean_task

    def _set_dag_final_tasks(
        self, execute_job_cluster_local_id, dummy_terminate_job_cluster_task
    ):
        """
        The final task of the DAG will either be the dummy_terminate_job_cluster_task, or the get_table_metrics_task.
        This method creates the metrics task if it should be included in the workflow, and sets the dependencies. Otherwise,
        it simply returns the dummy_terminate_job_cluster_task.
        """

        # This guarantees that the task will be added only at the first local job cluster subdag.
        if (
            self._check_include_get_table_metrics_task(
                self.workflow_args["tables_customization"]
            )
            and execute_job_cluster_local_id == 1
        ):
            first_metrics_task, last_metrics_task = self._create_generate_metrics_task_group(
                self.generate_database_table_metrics_task_creator,
                self.sync_metadata_task_creator,
            )
            last_metrics_task >> dummy_terminate_job_cluster_task
            return first_metrics_task
        else:
            return dummy_terminate_job_cluster_task
