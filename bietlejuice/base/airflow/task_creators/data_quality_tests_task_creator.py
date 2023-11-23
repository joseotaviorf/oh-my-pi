from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class DataQualityTestsTaskCreator(BaseTaskCreator):
    """
    Creates the task that execute data quality tests. This is not necessary for when there is no tests. That should be
    determined by the workflow.
    """

    _TASK_ID_TEMPLATE = "data-quality-tests-{layer}-{schema}-{table_name}"

    DEFAULT_SPARK_JOB_NAME = "data_quality_tests"

    def create_task(
        self, table_attributes: TableAttributes, execution_date: str
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes, execution_date)

        return self._create_spark_job_task(
            self.DEFAULT_SPARK_JOB_NAME, task_id, parameters
        )

    def _get_parameters(
        self, table_attributes: TableAttributes, execution_date: str
    ) -> list:
        parameters = [
            self.environment_attributes.environment,
            execution_date,
            self.environment_attributes.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            table_attributes.table_name,
        ]

        return parameters
