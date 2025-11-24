from typing import Union
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class LoadWonkaTaskCreator(BaseTaskCreator):
    """Creates the task that loads data from the transactional layer of a Change Data Capture (CDC) pipeline into the raw layer."""

    SPARK_JOB_NAME = "load_wonka"

    def _get_parameters(self) -> list:
        return [
            self.dag_execution_context.workflow_args["wonka_config"]["pipeline_runner"]
        ]

    def create_task(
        self, table_attributes: Union[TableAttributes, list]
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        """
        Creates a task that runs a Wonka pipeline.

        Since a Wonka pipeline can generate multiple tables (i.e. historical and latest),
        we only need to run the task once.
        """
        if isinstance(table_attributes, list) and len(table_attributes) > 1:
            table_attributes = table_attributes[0]

        parameters = self._get_parameters()

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            f"load-wonka-{table_attributes.table_name}",
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )
