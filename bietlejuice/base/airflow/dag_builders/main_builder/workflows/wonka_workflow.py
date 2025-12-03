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


class WonkaWorkflow(BaseWorkflow):
    """
    This workflow is responsible for creating dags for wonka
    """

    _WONKA_CUSTOM_SCHEMA = "wonka"

    def __init__(self, dag_args, workflow_args, cluster_args, dataset_dependencies):
        super().__init__(dag_args, workflow_args, cluster_args, dataset_dependencies)

        self.dag_id = f"quintoml.wonka.{self.dag_name.replace('-', '_')}"

    def build_dag(self):
        dag = super().dag_instance()

        # Set default schema to wonka if not set
        self.workflow_args["custom_schema"] = self._WONKA_CUSTOM_SCHEMA
        bucket = self.config_service.get_config("wonka_bucket")
        load_start_date, load_end_date = self._initialize_load_start_and_end_date()
        self.dag_execution_context = self._get_dag_execution_context(
            dag, bucket, load_start_date=load_start_date, load_end_date=load_end_date
        )
        self._initialize_task_creators(self.dag_execution_context)
        self._create_all_tasks()

        return dag

    def _get_dag_documentation(self):
        # The original _get_dag_documentation method couples orchestration abstraction
        # with the actual DAG code. This is problematic when DAG code is in a different repo.
        return "No docs available for this DAG."

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_databricks_version="12.2",
        )
        self.load_wonka_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_WONKA
        )
        self.load_cdf_to_datazord_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CDF_TO_DATAZORD, config_service=self.config_service
        )
        self.dummy_job_cluster_finished_task_creator = (
            task_creator_factory.get_task_creator(TaskEnum.DUMMY_JOB_CLUSTER_FINISHED)
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.skip_run_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SKIP_RUN
        )

    def __set_env_vars_from_dag_args(self, task, dag_args):
        task.cluster_configuration["spark_env_vars"]["PACKAGE_PATH"] = dag_args[
            "artifact_path"
        ]

    def _create_all_tasks(self) -> None:
        """
        Creates all the tasks for the workflow, and sets their internal dependencies
        """

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()

        # For the Wonka workflows, we want to be able to pass
        # some extra env vars to the task so we can parametrize
        # things related to the Feature Set pipelines.
        # Those parameters are stored in the dag args, and come
        # from the DAG declaration file in QuintoML.
        self.__set_env_vars_from_dag_args(execute_job_cluster_task, self.dag_args)

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> execute_job_cluster_task

        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        wonka_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.WONKA,
            self.workflow_args["wonka_config"]["name"],
        )

        load_wonka_task = self.load_wonka_task_creator.create_task(
            wonka_table_attributes
        )

        tables_to_optimize = [wonka_table_attributes]

        datazord_config = self.workflow_args.get("datazord_config")
        if datazord_config:
            wonka_latest_table_attributes = TableAttributes(
                self.dag_args,
                self.workflow_args,
                LayerEnum.WONKA,
                datazord_config["table"],
            )

            tables_to_optimize.append(wonka_latest_table_attributes)

            load_cdf_to_datazord_task = (
                self.load_cdf_to_datazord_task_creator.create_task(
                    wonka_latest_table_attributes,
                    key_columns=(
                        datazord_config["key_columns"]
                        if "key_columns" in datazord_config
                        else []
                    ),
                )
            )

        # We keep only a single "optimize table" task that will be used to optimize all the tables
        optimize_delta_tables_task = self.optimize_delta_table_task_creator.create_task(
            tables_to_optimize
        )

        (
            execute_job_cluster_task
            >> load_wonka_task
            >> optimize_delta_tables_task
            >> dummy_terminate_job_cluster_task
        )

        if datazord_config:
            (
                optimize_delta_tables_task
                >> load_cdf_to_datazord_task
                >> dummy_terminate_job_cluster_task
            )
