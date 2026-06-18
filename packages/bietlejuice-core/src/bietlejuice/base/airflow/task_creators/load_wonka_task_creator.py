from typing import Union

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class LoadWonkaTaskCreator(LoadTaskCreator):
    """Creates the task that loads data from the transactional layer of a Change Data Capture (CDC) pipeline into the raw layer."""

    _TASK_ID_TEMPLATE = "load-wonka-{table_name}"
    SPARK_JOB_NAME = "load_wonka"

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        parameters = [
            self.dag_execution_context.workflow_args["wonka_config"]["pipeline_runner"]
        ]
        if getattr(self.dag_execution_context, "is_validation", False):
            target_db, target_table = table_attributes.get_validation_write_target()
            parameters.extend(
                [
                    "--target-database-name",
                    target_db,
                    "--target-table-name",
                    target_table,
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
        )

    def create_task(
        self, table_attributes: Union[TableAttributes, list]
    ) -> BaseOperator:
        """
        Creates a task that runs a Wonka pipeline.

        Since a Wonka pipeline can generate multiple tables (i.e. historical and latest),
        we only need to run the task once.
        """
        if isinstance(table_attributes, list) and len(table_attributes) > 1:
            table_attributes = table_attributes[0]

        return super().create_task(table_attributes)
