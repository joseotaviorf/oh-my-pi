from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
import json


class GeneratePostgresTableMetricsTaskCreator(BaseTaskCreator):
    """Creates the task that extracts data from a Postgres database, calculates its simple metrics (count, count_distinct, avg, max, min) and load into our clean layer."""

    SPARK_JOB_NAME = "generate_postgres_table_metrics"

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = "get-metrics"
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)

    def _get_table_metrics(self) -> dict:
        tables_customization = self.dag_execution_context.workflow_args.get(
            "tables_customization"
        )
        table_metrics = {}

        for raw_table_name, table_information in tables_customization.items():

            if "get_table_metrics" in table_information:
                table_metrics[raw_table_name] = {}
                table_metrics[raw_table_name]["metrics"] = table_information[
                    "get_table_metrics"
                ]
                table_metrics[raw_table_name][
                    "clean_table_name"
                ] = table_information.get("clean_table_name", raw_table_name)

        return table_metrics

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        dbutils_secret_key = self.dag_execution_context.workflow_args.get(
            "dbutils_secret_key",
            f"{self.dag_execution_context.workflow_args.get('custom_schema')}_DB".upper(),
        )
        db_schema = self.dag_execution_context.workflow_args.get("db_schema", "public")
        table_metrics = self._get_table_metrics()

        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            dbutils_secret_key,
            table_attributes.schema,
            table_attributes.table_name,
            self.dag_execution_context.execution_date,
            db_schema,
            json.dumps(table_metrics),
            self.dag_execution_context.dag.dag_id,
        ]
