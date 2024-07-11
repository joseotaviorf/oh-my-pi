from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
import json


class LoadPostgresRawTaskCreator(BaseTaskCreator):
    """Creates the task that extracts data from a Postgres Database and into our raw layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_postgres_raw"

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)

    def _get_load_options(self, table_attributes: TableAttributes) -> str:
        default_load_options = self.dag_execution_context.workflow_args.get(
            "load_options", {}
        )
        table_load_options = table_attributes.table_customization.get(
            "load_options", default_load_options
        )
        return json.dumps(table_load_options)

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        dbutils_secret_key = self.dag_execution_context.workflow_args.get(
            "dbutils_secret_key", f"{table_attributes.schema.upper()}_DB"
        )
        unixtime_measure = table_attributes.table_customization.get(
            "unixtime_measure", ""
        )
        date_filter_column = table_attributes.table_customization.get(
            "date_filter_column", ""
        )
        db_schema = table_attributes.table_customization.get("db_schema", "public")
        load_options = self._get_load_options(table_attributes)
        read_from_sql = table_attributes.table_customization.get("read_from_sql", "")

        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            dbutils_secret_key,
            table_attributes.schema,
            table_attributes.table_name,
            unixtime_measure,
            table_attributes.extraction_type,
            str(table_attributes.partitions),
            date_filter_column,
            self.dag_execution_context.execution_date,
            db_schema,
            load_options,
            read_from_sql,
            self.dag_execution_context.load_start_date,
            self.dag_execution_context.load_end_date,
        ]
