from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class LoadCDCTransactionalTaskCreator(BaseTaskCreator):
    """Creates the task that loads data from the landing zone of a Change Data Capture (CDC) pipeline into the transactional layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_cdc_transactional"

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = [
            self.environment_attributes.environment,
            self.environment_attributes.bucket,
            table_attributes.schema,
            table_attributes.table_name,
        ]

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
