from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.services.configuration_service import ConfigurationService


class LoadWonkaTaskCreator(LoadTaskCreator):
    """Creates the task that loads data from the transactional layer of a Change Data Capture (CDC) pipeline into the raw layer."""

    _TASK_ID_TEMPLATE = "load-wonka-{table_name}"
    SPARK_JOB_NAME = "load_wonka"

    # Wonka runs from a dedicated PEX virtualenv created on EMR by
    # install_pex_generic.sh (venv_dir=/home/hadoop/venv). Shared bietlejuice
    # jobs (optimize/vacuum) must keep using the default EMR Python, so this is
    # applied only to the load-wonka step, not cluster-wide.
    # For Wonka DAGs, this path for the PEX-based Python interpreter needs to be the same as the one
    # set in `packages/bietlejuice-compiler/scripts/wonka/install_pex_generic.sh`.
    _PEX_PYTHON_INTERPRETER_PATH = "/home/hadoop/venv/bin/python"

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        pipeline_package = self.dag_execution_context.dag_args["name"].replace("-", "_")
        parameters = [pipeline_package]
        if getattr(self.dag_execution_context, "is_validation", False):
            target_db, target_table = table_attributes.get_validation_write_target()
            parameters.extend(
                [
                    "--target-database-name",
                    target_db,
                    "--target-table-name",
                    target_table,
                    "--datalake-bucket",
                    ConfigurationService().get_config("datalake_bucket"),
                ]
            )
        return parameters

    def _create_base_load_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
            # Note: python_interpreter_path is ignored when running on Databricks
            python_interpreter_path=self._PEX_PYTHON_INTERPRETER_PATH,
        )
