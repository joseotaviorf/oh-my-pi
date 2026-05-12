"""
Task creator for QUBE metric build jobs.

Creates Airflow tasks that execute QUBE build_metric function as Spark jobs on Databricks.
"""

import json

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class BuildQubeMetricTaskCreator(BaseTaskCreator):
    """
    Creates the task that builds QUBE metric tables.
    """

    _TASK_ID_TEMPLATE = "build-qube-metric-{table_name}"
    SPARK_JOB_NAME = "metrics/build_metric"

    def create_task(self, table_attributes: TableAttributes) -> BaseOperator:
        """
        Creates a task that runs a QUBE metric build job.

        Args:
            table_attributes: TableAttributes containing spec path and other parameters

        Returns:
            Airflow operator for the metric build step (Databricks or EMR).
        """
        task_id = self.generate_task_id(table_attributes)

        # Get spec content from table_customization (full spec dict)
        # Remove spec_path if present, keep only the spec content
        spec_content = dict(table_attributes.table_customization)
        spec_content.pop("spec_path", None)  # Remove spec_path if it exists

        # Convert spec to JSON string
        spec_json = json.dumps(spec_content)

        # Build job parameters
        parameters = [
            "--spec-json",
            spec_json,
            "--env",
            self.dag_execution_context.environment,
            "--date",
            self.dag_execution_context.execution_date,
        ]

        # Add optional parameters from table customization
        if "db_prefix" in table_attributes.table_customization:
            parameters.extend(
                ["--db-prefix", table_attributes.table_customization["db_prefix"]]
            )
        if "warehouse" in table_attributes.table_customization:
            parameters.extend(
                ["--warehouse", table_attributes.table_customization["warehouse"]]
            )

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            spark_job_prefix="",
            execution_timeout_hours=4,  # Metrics may take longer
        )
