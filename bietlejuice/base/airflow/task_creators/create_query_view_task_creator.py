from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
import json


class CreateQueryViewTaskCreator(BaseTaskCreator):
    """Creates the task that creates views on both Databricks and Trino."""

    _TASK_ID_TEMPLATE = "create-query-view-{layer}-{table_name}"
    SPARK_JOB_NAME = "create_query_view"

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        """Get parameters for the Spark job that creates views on both Databricks and Trino."""
        extra_query_template_params = self._get_extra_query_template_params(
            table_attributes
        )
        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            self.dag_execution_context.dag_args["name"],
            table_attributes.table_name,
            self.dag_execution_context.execution_date,
            json.dumps(
                self.dag_execution_context.workflow_args.get(
                    "spark_session_configs", {}
                )
            ),
            json.dumps(extra_query_template_params),
            self.dag_execution_context.execution_date,
            "--table-privileges",
            json.dumps(table_attributes.table_privileges),
        ]

    def _get_extra_query_template_params(
        self, table_attributes: TableAttributes
    ) -> dict:
        default_extra_query_template_params = self.dag_execution_context.workflow_args.get(
            "extra_query_template_params", {}
        )
        extra_query_template_params = table_attributes.table_customization.get(
            "extra_query_template_params", default_extra_query_template_params
        )
        if "load_start_date" not in extra_query_template_params:
            extra_query_template_params[
                "load_start_date"
            ] = self.dag_execution_context.load_start_date
        if "load_end_date" not in extra_query_template_params:
            extra_query_template_params[
                "load_end_date"
            ] = self.dag_execution_context.load_end_date

        return extra_query_template_params
