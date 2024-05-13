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

        raw_tables = self._get_raw_tables()
        clean_tables = self._get_clean_tables(raw_tables)

        self._create_all_tasks(raw_tables, clean_tables)

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
        self.generate_postgres_table_metrics_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.GENERATE_POSTGRES_TABLE_METRICS
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
        self, raw_tables: List[TableAttributes], clean_tables: List[TableAttributes]
    ) -> None:
        """Creates all the tasks for the workflow and sets their dependencies."""

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        optimize_clean_task = self.optimize_delta_table_task_creator.create_task(
            clean_tables
        )
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        last_task = self._create_generate_metrics_task(dummy_terminate_job_cluster_task)

        for raw_table, clean_table in zip(raw_tables, clean_tables):
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                raw_table,
                dummy_terminate_job_cluster_task=dummy_terminate_job_cluster_task,
            )
            clean_initial_task, clean_final_task = self._create_clean_tasks(
                clean_table,
                optimize_clean_task,
                dummy_terminate_job_cluster_task=dummy_terminate_job_cluster_task,
            )
            execute_job_cluster_task >> raw_initial_task
            raw_final_task >> clean_initial_task
            clean_final_task >> dummy_terminate_job_cluster_task

        optimize_clean_task >> last_task

    def _create_raw_tasks(
        self, raw_table_attributes: TableAttributes, dummy_terminate_job_cluster_task
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

            (load_raw_task >> sync_metadata >> dummy_terminate_job_cluster_task)

        if self._check_include_data_quality_task(raw_table_attributes):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes
            )
            (
                load_raw_task
                >> data_quality_tests_raw_task
                >> dummy_terminate_job_cluster_task
            )

        return load_raw_task, load_raw_task

    def _create_clean_tasks(
        self,
        clean_table_attributes: TableAttributes,
        optimize_clean_task: dict,
        dummy_terminate_job_cluster_task,
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
                clean_table_attributes
            )

            last_clean_task = sync_metadata

            (load_clean_task >> register_table >> sync_metadata)

        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality_tests_clean_task = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            (
                load_clean_task
                >> data_quality_tests_clean_task
                >> dummy_terminate_job_cluster_task
            )

        return load_clean_task, last_clean_task

    def _should_add_get_table_metrics(self, tables_customization: dict) -> bool:
        if self.workflow_args["database_type"] != "postgres":
            return False
        for table_parameters in tables_customization.values():
            if "get_table_metrics" in table_parameters:
                return True
        return False

    def _create_generate_metrics_task(self, dummy_terminate_job_cluster_task) -> Tuple:
        """
        Creates the generate table metrics task when requested, sets the dependencies between the tasks and returns the last task of the dependency flow.
        """

        if self._should_add_get_table_metrics(
            self.workflow_args["tables_customization"]
        ):
            clean_metrics_table_attributes = TableAttributes(
                self.dag_args,
                self.workflow_args,
                LayerEnum.CLEAN,
                "table_ingestion_metrics",
                table_customization={"custom_schema": "data_quality_ingestion_metrics"},
            )

            sync_metadata = self.sync_metadata_task_creator.create_task(
                clean_metrics_table_attributes
            )

            get_table_metrics_task = self.generate_postgres_table_metrics_task_creator.create_task(
                clean_metrics_table_attributes
            )

            get_table_metrics_task >> sync_metadata >> dummy_terminate_job_cluster_task

            metrics_task = get_table_metrics_task
        else:
            metrics_task = (
                dummy_terminate_job_cluster_task
            )  # If the metrics task should not be included in the workflow, the terminate job cluster task is returned

        return metrics_task
