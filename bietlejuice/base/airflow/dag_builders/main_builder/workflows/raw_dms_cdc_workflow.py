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


class RawDMSCDCWorkflow(BaseWorkflow):
    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)

    def build_dag(self):
        dag = self.dag_instance()
        bucket = self.config_service.get_config("datalake_bucket")
        incoming_bucket_config_name = self.workflow_args.get(
            "incoming_bucket_config_name"
        )
        incoming_bucket = self.config_service.get_config(incoming_bucket_config_name)
        load_start_date = self.workflow_args.get("extra_query_template_params", {}).get(
            "load_start_date",
            "{{ get_date_param(dag_run, yesterday_ds, 'load_start_date') }}",
        )
        load_end_date = self.workflow_args.get("extra_query_template_params", {}).get(
            "load_end_date", "{{ get_date_param(dag_run, ds, 'load_end_date') }}"
        )
        dag_execution_context = self._get_dag_execution_context(
            dag,
            bucket,
            load_start_date=load_start_date,
            load_end_date=load_end_date,
            incoming_bucket=incoming_bucket,
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
        self.load_dms_cdc_raw_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DMS_CDC_RAW
        )
        self.load_dms_cdc_clean_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DMS_CDC_CLEAN, self.config_service
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
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )

    def _get_raw_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the raw layer"""
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
        dag_final_tasks = self._set_dag_final_tasks()
        optimize_raw_task = self.optimize_delta_table_task_creator.create_task(
            raw_tables,
            parallelism=2,  # Lower because we don't want to overload the cluster while the next layer is being loaded
        )
        optimize_clean_task = self.optimize_delta_table_task_creator.create_task(
            clean_tables
        )

        for raw_table, clean_table in zip(raw_tables, clean_tables):
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                raw_table, optimize_raw_task, dag_final_tasks=dag_final_tasks
            )
            clean_initial_task, clean_final_task = self._create_clean_tasks(
                clean_table, optimize_clean_task, dag_final_tasks=dag_final_tasks
            )
            execute_job_cluster_task >> raw_initial_task
            raw_final_task >> clean_initial_task
            clean_final_task >> dag_final_tasks

        optimize_raw_task >> dag_final_tasks
        optimize_clean_task >> dag_final_tasks

    def _create_raw_tasks(
        self, raw_table_attributes: TableAttributes, optimize_raw_task, dag_final_tasks
    ) -> Tuple:
        """
        Creates raw tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        load_raw_task = self.load_dms_cdc_raw_task_creator.create_task(
            raw_table_attributes
        )

        # We need to create a new TableAttributes object with the table_name in lower case, to follow the convention
        # The exception is for the load_raw_task, since we need the original table_name to load data from the incoming layer.
        # It is then forced to lowercase in the Spark job.
        raw_table_attributes_lower_case = TableAttributes.from_attributes(
            raw_table_attributes, table_name=raw_table_attributes.table_name.lower()
        )
        load_raw_task >> optimize_raw_task

        if self._check_include_sync_hive_tasks(raw_table_attributes_lower_case):
            register_delta_table_raw_task = self.register_delta_table_task_creator.create_task(
                raw_table_attributes_lower_case
            )
            load_raw_task >> register_delta_table_raw_task
            if self._check_include_propagate_metadata_task(raw_table_attributes):
                propagate_table_lineage_raw_task = self.sync_metadata_task_creator.create_task(
                    raw_table_attributes, "--bypass-hive"
                )
                (
                    register_delta_table_raw_task
                    >> propagate_table_lineage_raw_task
                    >> dag_final_tasks
                )
            else:
                register_delta_table_raw_task >> dag_final_tasks

        if self._check_include_data_quality_task(raw_table_attributes_lower_case):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes_lower_case
            )
            (load_raw_task >> data_quality_tests_raw_task >> dag_final_tasks)

        return load_raw_task, load_raw_task

    def _create_clean_tasks(
        self,
        clean_table_attributes: TableAttributes,
        optimize_clean_task,
        dag_final_tasks,
    ) -> Tuple:
        """
        Creates clean tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """

        load_clean_task = self.load_dms_cdc_clean_task_creator.create_task(
            clean_table_attributes
        )
        load_clean_task >> optimize_clean_task
        last_clean_task = load_clean_task

        if self._check_include_sync_hive_tasks(clean_table_attributes):
            register_delta_table_clean_task = self.register_delta_table_task_creator.create_task(
                clean_table_attributes
            )

            sync_metadata_clean_task = self.sync_metadata_task_creator.create_task(
                clean_table_attributes, "--bypass-hive"
            )
            last_clean_task = sync_metadata_clean_task

            (
                load_clean_task
                >> register_delta_table_clean_task
                >> sync_metadata_clean_task
            )

        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality_tests_clean_task = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            (load_clean_task >> data_quality_tests_clean_task >> dag_final_tasks)

        return load_clean_task, last_clean_task

    def _set_dag_final_tasks(self):
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        return dummy_terminate_job_cluster_task
