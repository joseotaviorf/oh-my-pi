from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class LoadCDCCleanTaskCreator(BaseTaskCreator):
    """Creates the task that loads data from the raw layer of a Change Data Capture (CDC) pipeline into the clean layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_cdc_clean"

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        raw_table_id = table_attributes.table_customization.get("raw_table_id")
        clean_table_id = table_attributes.table_customization.get(
            "clean_table_id", raw_table_id
        )

        return [
            self.dag_execution_context.dag_args["name"],
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            table_attributes.schema,
            table_attributes.table_name,
            self.dag_execution_context.execution_date,
            clean_table_id,
        ]

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
