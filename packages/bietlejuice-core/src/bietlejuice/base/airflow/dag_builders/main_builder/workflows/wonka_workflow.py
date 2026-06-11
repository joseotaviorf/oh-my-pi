import copy
import logging

from bietlejuice.base.airflow.cluster_config_resolver import is_airflow_emr_cluster
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
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
from bietlejuice.base.pipeline.environment_enum import EnvironmentEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum

logger = logging.getLogger("WonkaWorkflow")


class WonkaWorkflow(BaseWorkflow):
    """
    This workflow is responsible for creating dags for wonka
    """

    _WONKA_CUSTOM_SCHEMA = "wonka"
    _WONKA_DEFAULT_CLUSTER_CONFIG_KEY = "wonka_cluster"
    _INSTALL_PEX_GENERIC_SCRIPT = "install_pex_generic.sh"

    def __init__(
        self, dag_args, workflow_args, cluster_args, dataset_dependencies, **kwargs
    ):
        super().__init__(
            dag_args,
            workflow_args,
            cluster_args,
            dataset_dependencies,
            **kwargs,
        )

        if (
            self.env == EnvironmentEnum.PROD
            and self.cluster_args.get("type") == "wonka_cluster_emr"
        ):
            raise RuntimeError(
                "Wonka EMR is not enabled in prod; use cluster.type: wonka_cluster"
            )

        wonka_dag_id = f"quintoml.wonka.{self.dag_name.replace('-', '_')}"
        if self.is_validation:
            self.dag_id = f"{wonka_dag_id}{self.VALIDATION_DAG_SUFFIX}"
        else:
            self.dag_id = wonka_dag_id

        # Merge the Wonka cluster preset (from declaration `type`, default `wonka_cluster`)
        # with the DAG declaration `cluster:` block into `self.cluster_args`.
        wonka_cluster_config_key = self.cluster_args.get(
            "type", self._WONKA_DEFAULT_CLUSTER_CONFIG_KEY
        )
        wonka_cluster_preset = self.config_service.get_config(wonka_cluster_config_key)
        self.cluster_args = self._get_deep_updated_dict(
            wonka_cluster_preset, self.cluster_args
        )

        # Merge custom_configurations.spark_conf into top-level spark_conf so the
        # Databricks Jobs API receives all spark configs (it only uses top-level spark_conf).
        custom_spark_conf = self.cluster_args.get("custom_configurations", {}).get(
            "spark_conf"
        )
        if custom_spark_conf and isinstance(custom_spark_conf, dict):
            self.cluster_args = self._get_deep_updated_dict(
                self.cluster_args, {"spark_conf": custom_spark_conf}
            )

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
        logger.info(
            f"m=build_dag, msg=DAG build completed successfully, dag_id={self.dag_id}"
        )

        return dag

    @staticmethod
    def _get_deep_updated_dict(old_values, new_values):
        """
        Return a new dict: deep merge of ``old_values`` with ``new_values`` (new wins on
        conflicts). Dict values are merged recursively; lists and scalars are replaced.

        Neither ``old_values`` nor ``new_values`` is modified.
        """
        if new_values is None:
            new_values = {}
        if not isinstance(new_values, dict):
            raise TypeError("new_values must be a dict or None")
        if old_values is None:
            old_values = {}
        if not isinstance(old_values, dict):
            raise TypeError("old_values must be a dict or None")

        result = copy.deepcopy(old_values)
        for key, value in new_values.items():
            if (
                key in result
                and isinstance(result[key], dict)
                and isinstance(value, dict)
            ):
                result[key] = WonkaWorkflow._get_deep_updated_dict(result[key], value)
            else:
                result[key] = copy.deepcopy(value)
        return result

    def _get_dag_documentation(self):
        # The original _get_dag_documentation method couples orchestration abstraction
        # with the actual DAG code. This is problematic when DAG code is in a different repo.
        return "No docs available for this DAG."

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_cluster_runtime_version="12.2",
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
        logger.info(
            "m=_initialize_task_creators, msg=All task creators initialized successfully for DAG {self.dag_id}"
        )

    @staticmethod
    def _patch_emr_install_pex_bootstrap_args(
        cluster_configuration: dict, artifact_path: str
    ) -> None:
        for init_script in cluster_configuration.get("init_scripts", []):
            destination = init_script.get("s3", {}).get("destination", "")
            if destination.endswith(WonkaWorkflow._INSTALL_PEX_GENERIC_SCRIPT):
                init_script["args"] = [artifact_path]
                return

    def __set_env_vars_from_dag_args(self, task, dag_args):
        cluster_configuration = task.cluster_configuration
        spark_env_vars = cluster_configuration.setdefault("spark_env_vars", {})
        artifact_path = dag_args["artifact_path"]
        spark_env_vars["PACKAGE_PATH"] = artifact_path

        if is_airflow_emr_cluster(cluster_configuration.get("spark_version", "")):
            self._patch_emr_install_pex_bootstrap_args(
                cluster_configuration, artifact_path
            )

    def _create_all_tasks(self) -> None:
        """
        Creates all the tasks for the workflow, and sets their internal dependencies
        """
        created_tasks_ids = []

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        created_tasks_ids.append(execute_job_cluster_task.task_id)

        # For the Wonka workflows, we want to be able to pass
        # some extra env vars to the task so we can parametrize
        # things related to the Feature Set pipelines.
        # Those parameters are stored in the dag args, and come
        # from the DAG declaration file in QuintoML.
        self.__set_env_vars_from_dag_args(execute_job_cluster_task, self.dag_args)

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            created_tasks_ids.append(skip_run_task.task_id)
            skip_run_task >> execute_job_cluster_task

        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        created_tasks_ids.append(dummy_terminate_job_cluster_task.task_id)
        cluster_completion_sink = get_job_cluster_completion_sink(
            self.dag_execution_context,
            execute_job_cluster_task,
            dummy_terminate_job_cluster_task,
            None,
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
        created_tasks_ids.append(load_wonka_task.task_id)

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
            created_tasks_ids.append(load_cdf_to_datazord_task.task_id)

        # We keep only a single "optimize table" task that will be used to optimize all the tables
        optimize_delta_tables_task = self.optimize_delta_table_task_creator.create_task(
            tables_to_optimize
        )
        created_tasks_ids.append(optimize_delta_tables_task.task_id)

        execute_job_cluster_task >> load_wonka_task >> optimize_delta_tables_task

        if datazord_config:
            (
                optimize_delta_tables_task
                >> load_cdf_to_datazord_task
                >> cluster_completion_sink
            )
        else:
            optimize_delta_tables_task >> cluster_completion_sink

        attach_emr_job_cluster_finished_work_prerequisites(
            self.dag_execution_context,
            dummy_terminate_job_cluster_task,
            cluster_completion_sink=cluster_completion_sink,
        )

        DatasetAdder.attach_reprocessing_guard(
            execute_job_cluster_task, self.dag_execution_context
        )

        task_list = ", ".join(created_tasks_ids)
        logger.info(
            f"DAG {self.dag_name} was created with the following tasks: {{{task_list}}}"
        )
