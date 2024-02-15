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


class RawCDCWorkflow(BaseWorkflow):
    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)

    def build_dag(self):
        dag = super().dag_instance()
        bucket = self.config_service.get_config("datalake_bucket")
        dag_execution_context = self._get_dag_execution_context(dag, bucket)
        self._initialize_task_creators(dag_execution_context)
        tables_customization = self.workflow_args["tables_customization"]
        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        for raw_table_name, table_parameters in tables_customization.items():
            self._check_table_id_parameter(table_parameters)
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                table_name=raw_table_name,
                dummy_terminate_job_cluster_task=dummy_terminate_job_cluster_task,
            )
            clean_initial_task, clean_final_task = self._create_clean_tasks(
                table_name=table_parameters.get("clean_table_name", raw_table_name),
                table_customization=table_parameters,
                dummy_terminate_job_cluster_task=dummy_terminate_job_cluster_task,
            )
            execute_job_cluster_task >> raw_initial_task
            raw_final_task >> clean_initial_task
            clean_final_task >> dummy_terminate_job_cluster_task

        return dag

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER, self.config_service
        )
        self.load_transactional_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CDC_TRANSACTIONAL
        )
        self.load_cdc_raw_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CDC_RAW
        )
        self.load_cdc_clean_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CDC_CLEAN
        )
        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.REGISTER_DELTA_TABLE
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
        self.propagate_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.PROPAGATE_METADATA
        )
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )

    def _create_raw_tasks(
        self, table_name: str, dummy_terminate_job_cluster_task
    ) -> Tuple:
        """
        Creates raw tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        transactional_table_attributes = TableAttributes(
            self.dag_args, self.workflow_args, LayerEnum.TRANSACTIONAL, table_name
        )

        load_cdc_transactional_task = self.load_transactional_task_creator.create_task(
            transactional_table_attributes
        )

        raw_table_attributes = TableAttributes.from_attributes(
            transactional_table_attributes, layer=LayerEnum.RAW
        )

        load_raw_task = self.load_cdc_raw_task_creator.create_task(raw_table_attributes)

        register_delta_table_raw_task = self.register_delta_table_task_creator.create_task(
            raw_table_attributes
        )

        (load_cdc_transactional_task >> load_raw_task >> register_delta_table_raw_task)

        if self._check_include_propagate_metadata_task(raw_table_attributes):
            propagate_table_lineage_raw_task = self.propagate_metadata_task_creator.create_task(
                raw_table_attributes
            )
            (
                register_delta_table_raw_task
                >> propagate_table_lineage_raw_task
                >> dummy_terminate_job_cluster_task
            )
        else:
            register_delta_table_raw_task >> dummy_terminate_job_cluster_task

        if self._check_include_data_quality_task(raw_table_attributes):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes
            )
            (
                load_raw_task
                >> data_quality_tests_raw_task
                >> dummy_terminate_job_cluster_task
            )

        return load_cdc_transactional_task, load_raw_task

    def _create_clean_tasks(
        self,
        table_name: str,
        table_customization: dict,
        dummy_terminate_job_cluster_task,
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

        load_clean_task = self.load_cdc_clean_task_creator.create_task(
            clean_table_attributes
        )

        register_delta_table_clean_task = self.register_delta_table_task_creator.create_task(
            clean_table_attributes
        )

        propagate_table_metadata_clean_task = self.propagate_metadata_task_creator.create_task(
            clean_table_attributes
        )

        (
            load_clean_task
            >> register_delta_table_clean_task
            >> propagate_table_metadata_clean_task
        )

        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality_tests_clean_task = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            (
                load_clean_task
                >> data_quality_tests_clean_task
                >> dummy_terminate_job_cluster_task
            )

        return load_clean_task, propagate_table_metadata_clean_task

    def _check_table_id_parameter(self, table_parameters):
        """
        Checks if the parameter table_id is informed in the dag declaration
        """
        table_id = table_parameters.get("raw_table_id")
        if table_id is None:
            raise ValueError(
                "The parameter 'table_id' cannot be None and must be informed in the dag declaration for each table."
            )
        return
