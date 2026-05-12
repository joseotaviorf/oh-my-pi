from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.task_creators.register_delta_table_task_creator import (
    RegisterDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class QubeRegisterDeltaTableTaskCreator(RegisterDeltaTableTaskCreator):
    """
    Custom task creator for QUBE workflows to register Delta tables in Trino.

    QUBE workflows use a custom base_spark_jobs_path (qube/jobs/), and this
    task creator points to the QUBE-specific register_delta_table.py located
    at qube/jobs/common/register_delta_table.py.
    """

    SPARK_JOB_NAME = "common/register_delta_table"

    def create_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)

        # Extract windows from qube_specs (dimensions/measures/metrics all have windows)
        qube_specs = table_attributes.table_customization
        windows = qube_specs.get("windows", [1, 7, 28])

        # Normalize windows to list if it's a single integer
        if isinstance(windows, int):
            windows = [windows]

        # Convert windows list to comma-separated string
        windows_str = ",".join(str(w) for w in windows)

        parameters = [
            self.dag_execution_context.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            table_attributes.table_name,
            "--windows",
            windows_str,
        ]

        # The base path for QUBE is: {repo}/qube/jobs/
        # The register_delta_table.py is at: {repo}/qube/jobs/common/register_delta_table.py
        # So we use "common/register_delta_table" as the spark job name
        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
