from abc import ABC, abstractmethod
from datetime import timedelta
from os import path

from airflow.models.baseoperator import BaseOperator
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
from bietlejuice.base.airflow.task_creators.environment_attributes import (
    EnvironmentAttributes,
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

    def __init__(self, environment_attributes: EnvironmentAttributes) -> None:
        self.environment_attributes = environment_attributes

    @abstractmethod
    def create_task(self, table_attributes: TableAttributes = None) -> BaseOperator:
        """Returns an Airflow task."""

    def _create_spark_job_task(
        self, spark_job_name: str, task_id: str, job_parameters: list
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        """
        Returns a task that runs a Spark Job in the base spark jobs path, with the given name, task id, and parameters.
        Serves as an auxiliary function for subclasses, since most of them run in Spark Jobs.
        """

        return QuintoAndarDatabricksCheckJobTaskOperator(
            databricks_conn_id="databricks_job_cluster",
            dag=self.environment_attributes.dag,
            task_id=task_id,
            json={
                "spark_python_task": {
                    "python_file": path.join(
                        self.environment_attributes.base_spark_jobs_path,
                        f"{spark_job_name}.py",
                    ),
                    "parameters": job_parameters,
                }
            },
            execution_timeout=timedelta(hours=self._DEFAULT_EXECUTION_TIMEOUT_HOURS),
        )

    @classmethod
    def generate_task_id(cls, table_attributes: TableAttributes):
        """Generates the task id from the Task's default template, using attributes of a given table."""

        task_id = cls._TASK_ID_TEMPLATE.format(
            layer=table_attributes.layer.value,
            schema=table_attributes.schema,
            table_name=table_attributes.table_name,
        )
        return StringFormatter.slugify(task_id)
