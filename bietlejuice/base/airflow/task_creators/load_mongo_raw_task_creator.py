from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class LoadMongoRawTaskCreator(BaseTaskCreator):
    """Creates the task that extracts data from a MongoDB table and sink into the raw layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{schema}-{table_name}"
    SPARK_JOB_NAME = "load_mongo_raw"

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        date_filter_column = table_attributes.table_customization.get(
            "date_filter_column", ""
        )
        dbutils_secret_key = self.dag_execution_context.workflow_args.get(
            "dbutils_secret_key", f"{table_attributes.schema.upper()}_DB"
        )

        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            table_attributes.schema,
            table_attributes.table_name,
            table_attributes.extraction_type,
            str(table_attributes.partitions),
            date_filter_column,
            dbutils_secret_key,
            self.dag_execution_context.execution_date,
        ]
