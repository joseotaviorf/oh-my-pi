from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class SyncHivePartitionsTaskCreator(BaseTaskCreator):
    """
    Creates a task that sends a synchronous request to our Hive Metastore to
    update table partitions, synchronizing them to the partitions of the table
    already available at Databricks Metastore.
    """

    _TASK_ID_TEMPLATE = "sync-hive-metastore-partitions-{layer}-{schema}-{table_name}"
    SPARK_JOB_NAME = "sync_metastore_tables_partitions"

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = [
            self.dag_execution_context.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            "--table-name",
            table_attributes.table_name,
        ]

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
