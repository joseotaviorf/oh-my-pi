from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class LoadCDCRawTaskCreator(BaseTaskCreator):
    """Creates the task that loads data from the transactional layer of a Change Data Capture (CDC) pipeline into the raw layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_cdc_raw"

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        source_schema = self.dag_execution_context.workflow_args.get(
            "source_schema", table_attributes.schema
        )
        primary_keys = ",".join(
            table_attributes.table_customization.get("raw_primary_keys", [])
        )

        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.incoming_bucket,
            self.dag_execution_context.bucket,
            source_schema,
            table_attributes.schema,
            table_attributes.table_name,
            self.dag_execution_context.start_date,
            self.dag_execution_context.end_date,
            primary_keys,
        ]

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
