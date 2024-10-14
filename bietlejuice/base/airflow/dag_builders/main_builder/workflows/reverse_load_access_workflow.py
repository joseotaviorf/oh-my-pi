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
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class ReverseLoadAccessWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates Delta tables from sql files, in the Reverse Layer,
    and them exports them somewhere else using a custom Spark job.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)

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

        table_attributes, tables_with_queries = self._get_tables()
        for table in table_attributes:
            export_reverse_task = self.export_task_creator.create_task(table)

            if table.table_name in tables_with_queries:
                load_reverse_task = self.load_reverse_task_creator.create_task(table)
                optimize_delta_table_task = self.optimize_delta_table_task_creator.create_task(
                    [table]
                )
                execute_job_cluster_task >> load_reverse_task >> optimize_delta_table_task >> dummy_terminate_job_cluster_task
                load_reverse_task >> export_reverse_task
            else:
                execute_job_cluster_task >> export_reverse_task

            export_reverse_task >> dummy_terminate_job_cluster_task

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> execute_job_cluster_task

        return dag

    def _get_tables(self) -> Tuple[List[TableAttributes], List[str]]:
        """
        Returns the table attributes for all the tables in the reverse layer.
        It also returns a list of tables that have corresponding queries (not all of them do).
        """

        table_names_queries = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=LayerEnum.REVERSE.value
        )
        table_names_customization = list(
            self.workflow_args.get("tables_customization", []).keys()
        )

        # There may be queries without their own customization
        # Or customization without queries (direct export)
        table_names = set(table_names_queries + table_names_customization)
        return (
            [
                TableAttributes(
                    self.dag_args, self.workflow_args, LayerEnum.REVERSE, table_name
                )
                for table_name in table_names
            ],
            table_names_queries,
        )

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.skip_run_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SKIP_RUN
        )
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_databricks_version="12.2",
        )
        self.load_reverse_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DELTA
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.export_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CUSTOM, task_id_prefix="export"
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
