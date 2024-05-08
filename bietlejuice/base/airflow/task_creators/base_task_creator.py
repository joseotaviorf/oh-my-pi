from abc import ABC, abstractmethod
from datetime import timedelta
from os import path
from typing import Union

from airflow.models.baseoperator import BaseOperator
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.formatters.string_formatter import StringFormatter


class BaseTaskCreator(ABC):
    """
    Task creators are responsible for creating tasks of specific types, such as hive sync or load.
    This is the base class for all of them.
    """

    _DEFAULT_EXECUTION_TIMEOUT_HOURS = 2
    """How many hours of execution until timeout."""

    _TASK_ID_TEMPLATE = "prefix-{layer}-{table_name}"
    """Used to generate the task name. Supports {layer}, {table_name} and {schema} as placeholders. Override in subclasses."""

    def __init__(self, dag_execution_context: DagExecutionContext) -> None:
        self.dag_execution_context = dag_execution_context

    @abstractmethod
    def create_task(
        self, table_attributes: Union[TableAttributes, list] = None
    ) -> BaseOperator:
        """Returns an Airflow task."""

    def _create_spark_job_task(
        self,
        spark_job_name: str,
        task_id: str,
        job_parameters: list,
        spark_job_prefix: str = None,
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        """
        Returns a task that runs a Spark Job in the base spark jobs path, with the given name, task id, and parameters.
        Serves as an auxiliary function for subclasses, since most of them run in Spark Jobs.

        spark_job_name: The name of the Spark Job to be run, without the path or extension.
        task_id: The task id.
        job_parameters: The parameters to be passed to the Spark Job.
        spark_job_prefix: If provided, it will replace /base/ in the path of the Spark Job.
        """
        spark_job_directory = self.dag_execution_context.base_spark_jobs_path
        if spark_job_prefix is not None:
            spark_job_directory = spark_job_directory.replace(
                "/spark_jobs/base/", f"/spark_jobs/{spark_job_prefix}/"
            )
        spark_job_path = path.join(spark_job_directory, f"{spark_job_name}.py")

        return QuintoAndarDatabricksCheckJobTaskOperator(
            databricks_conn_id="databricks_job_cluster",
            dag=self.dag_execution_context.dag,
            task_id=task_id,
            json={
                "spark_python_task": {
                    "python_file": spark_job_path,
                    "parameters": job_parameters,
                }
            },
            execution_timeout=timedelta(hours=self._DEFAULT_EXECUTION_TIMEOUT_HOURS),
        )

    @classmethod
    def generate_task_id(
        cls, table_attributes: TableAttributes, dynamic_template: str = None
    ) -> str:
        """
        Generates the task id from the Task's default template, using attributes of a given table.
        Optionally, you can pass a template other than the default one in _TASK_ID_TEMPLATE, using the dynamic_template argument.
        """

        template = dynamic_template or cls._TASK_ID_TEMPLATE
        task_id = template.format(
            layer=table_attributes.layer.value,
            schema=table_attributes.schema,
            table_name=table_attributes.table_name,
        )
        return StringFormatter.slugify(task_id)
