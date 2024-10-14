from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
import json


class LoadCustomTaskCreator(BaseTaskCreator):
    """Creates the task that loads a table using a custom Spark job"""

    def __init__(
        self, dag_execution_context: DagExecutionContext, task_id_prefix: str = "load"
    ) -> None:
        super().__init__(dag_execution_context)
        self.task_id_prefix = task_id_prefix

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        spark_job_name = self._generate_spark_job_name(table_attributes)
        task_id = self.generate_task_id(
            table_attributes,
            dynamic_template=f"{self.task_id_prefix}-{{layer}}-{{table_name}}",
        )
        parameters = self._generate_parameters(table_attributes)

        return self._create_spark_job_task(
            spark_job_name,
            task_id,
            parameters,
            spark_job_prefix=self._get_spark_job_prefix(table_attributes),
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )

    def _get_spark_job_prefix(self, table_attributes: TableAttributes) -> str:
        dag_name = self.dag_execution_context.dag_args["name"]
        default_spark_job_prefix = self.dag_execution_context.workflow_args.get(
            "spark_job_prefix", dag_name
        )
        table_load_spark_job_prefix = table_attributes.table_customization.get(
            "spark_job_prefix", default_spark_job_prefix
        )
        return table_load_spark_job_prefix

    def _generate_spark_job_name(self, table_attributes: TableAttributes) -> str:
        """
        Get the name of the Spark job that will be used to load the table. It will try to use
        the one in table_customization, if it doesn't exist, it will use the default one in
        workflow_args. It will also replace the placeholders with the actual values.
        """
        default_load_spark_job = self.dag_execution_context.workflow_args.get(
            "load_spark_job"
        )
        table_load_spark_job = table_attributes.table_customization.get(
            "load_spark_job", default_load_spark_job
        )
        assert (
            table_load_spark_job is not None
        ), "load_spark_job is required in workflow_args or tables_customization"
        return table_load_spark_job.format(
            dag_name=self.dag_execution_context.dag_args["name"],
            schema=table_attributes.schema,
            table_name=table_attributes.table_name,
            extraction_type=table_attributes.extraction_type,
        )

    def _generate_parameters(self, table_attributes: TableAttributes) -> list:
        """
        Read and parse the arguments list templates, converting to JSON and replacing the placeholders with the actual values.
        For example, if the argument is {"environment": "{environment}"}, it will be converted to
        {"environment": "prod"}.
        """

        unprocessed_arguments = self._get_unprocessed_arguments_list(table_attributes)
        arguments = []
        for unprocessed_argument in unprocessed_arguments:
            argument = self._parse_argument(unprocessed_argument, table_attributes)
            arguments.append(argument)
        return arguments

    def _get_unprocessed_arguments_list(
        self, table_attributes: TableAttributes
    ) -> list:
        """
        Get the list of arguments that will be passed to the Spark job. It will try to use the
        one in table_customization, if it doesn't exist, it will use the default one in
        workflow_args. Also, it will append the extra_spark_job_arguments if it exists.
        """

        default_arguments = self.dag_execution_context.workflow_args.get(
            "spark_job_arguments", []
        )
        table_arguments = table_attributes.table_customization.get(
            "spark_job_arguments", default_arguments
        )
        table_extra_arguments = table_attributes.table_customization.get(
            "extra_spark_job_arguments", []
        )
        return table_arguments + table_extra_arguments

    def _parse_argument(self, unprocessed_argument, table_attributes: TableAttributes):
        """
        Parse a single argument template, replacing the placeholders with the actual values.
        For example, if the argument is "{environment}", it will be converted to "prod".
        """

        if isinstance(unprocessed_argument, str):
            # The replace is necessary for it to work with Jinja. This is because the .format
            # method automatically replaces double curly braces with single curly braces.
            return (
                unprocessed_argument.replace("{{", "{{{{")
                .replace("}}", "}}}}")
                .format(
                    environment=self.dag_execution_context.environment,
                    bucket=self.dag_execution_context.bucket,
                    dag_name=self.dag_execution_context.dag_args["name"],
                    schema=table_attributes.schema,
                    table_name=table_attributes.table_name,
                    partitions=json.dumps(table_attributes.partitions),
                    extraction_type=table_attributes.extraction_type,
                    is_incremental=table_attributes.extraction_type == "incremental",
                    load_start_date=self.dag_execution_context.load_start_date,
                    load_end_date=self.dag_execution_context.load_end_date,
                )
            )
        if isinstance(unprocessed_argument, dict):
            return json.dumps(
                {
                    self._parse_argument(key, table_attributes): self._parse_argument(
                        value, table_attributes
                    )
                    for key, value in unprocessed_argument.items()
                }
            )
        if isinstance(unprocessed_argument, list):
            return [
                self._parse_argument(item, table_attributes)
                for item in unprocessed_argument
            ]
        return unprocessed_argument
