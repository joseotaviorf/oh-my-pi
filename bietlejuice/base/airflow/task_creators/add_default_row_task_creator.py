from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class AddDefaultRowTaskCreator(BaseTaskCreator):
    """Responsible for adding a default row with sk = -1 to a dim table."""

    _TASK_ID_TEMPLATE = "add-default-row-to-{layer}-{table_name}"
    SPARK_JOB_NAME = "add_default_row_to_dim"

    def __init__(
        self, dag_execution_context: DagExecutionContext, is_delta: bool = False
    ) -> None:
        super().__init__(dag_execution_context)
        self.is_delta = is_delta

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            table_attributes.schema,
            table_attributes.layer.value,
            table_attributes.table_name,
        ]
        if self.is_delta:
            parameters.append("--delta")
        return parameters

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
