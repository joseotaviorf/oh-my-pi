from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.job_cluster_engine import (
    METADATA_TASK_LIGHTWEIGHT_SPARK_CONF,
)
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class RegisterDeltaTableTaskCreator(BaseTaskCreator):
    """
    Creates a task that sends a synchronous request to our Hive Metastore to
    update table partitions, synchronizing them to the partitions of the table
    already available at Databricks Metastore.
    """

    _TASK_ID_TEMPLATE = "register-table-{layer}-{table_name}"
    SPARK_JOB_NAME = "register_delta_table"

    def create_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = [
            self.dag_execution_context.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            table_attributes.table_name,
        ]
        parameters.extend(table_attributes.spark_transformation_grade_args())

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            task_spark_conf=METADATA_TASK_LIGHTWEIGHT_SPARK_CONF,
        )
