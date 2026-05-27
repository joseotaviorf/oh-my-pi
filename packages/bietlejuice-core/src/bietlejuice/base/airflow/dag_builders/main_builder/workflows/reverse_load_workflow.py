from typing import List

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
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
    TaskEnum,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class ReverseLoadWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates Delta tables from sql files, in the Reverse Layer.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

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
        cluster_completion_sink = get_job_cluster_completion_sink(
            dag_execution_context,
            execute_job_cluster_task,
            dummy_terminate_job_cluster_task,
            None,
        )

        tables = self._get_tables()
        for table in tables:
            load_reverse_task = self.load_reverse_task_creator.create_task(table)
            if not self.is_validation:
                optimize_delta_table_task = (
                    self.optimize_delta_table_task_creator.create_task([table])
                )
                (
                    execute_job_cluster_task
                    >> load_reverse_task
                    >> optimize_delta_table_task
                    >> cluster_completion_sink
                )
            else:
                execute_job_cluster_task >> load_reverse_task >> cluster_completion_sink

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> execute_job_cluster_task

        attach_emr_job_cluster_finished_work_prerequisites(
            dag_execution_context,
            dummy_terminate_job_cluster_task,
            cluster_completion_sink=cluster_completion_sink,
        )

        DatasetAdder.attach_reprocessing_guard(
            execute_job_cluster_task, dag_execution_context
        )

        return dag

    def _get_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the reverse layer."""

        table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=LayerEnum.REVERSE.value
        )
        return [
            TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.REVERSE, table_name
            )
            for table_name in table_names
        ]

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.skip_run_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SKIP_RUN
        )
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_cluster_runtime_version="12.2",
        )
        self.load_reverse_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DELTA
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.dummy_job_cluster_finished_task_creator = (
            task_creator_factory.get_task_creator(TaskEnum.DUMMY_JOB_CLUSTER_FINISHED)
        )
