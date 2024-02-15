from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class LoadCDCTransactionalTaskCreator(BaseTaskCreator):
    """Creates the task that loads data from the landing zone of a Change Data Capture (CDC) pipeline into the transactional layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_cdc_transactional"

    def _get_cdc_connector_type(self) -> str:
        return self.dag_execution_context.workflow_args.get("cdc_connector_type", "")

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        partitions = ["year", "month", "day", "hour"]

        source_schema = self.dag_execution_context.workflow_args.get(
            "source_schema", table_attributes.schema
        )

        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            source_schema,
            table_attributes.schema,
            table_attributes.table_name,
            self.dag_execution_context.execution_date,
            self._get_cdc_connector_type(),
            str(partitions),
        ]
        return parameters

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
