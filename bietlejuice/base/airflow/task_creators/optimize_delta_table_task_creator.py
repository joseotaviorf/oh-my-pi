from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.formatters.string_formatter import StringFormatter
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
import json


class OptimizeDeltaTableTaskCreator(BaseTaskCreator):
    """
    Creates the task that optimizes Delta tables in S3. This task is essential for Delta tables, because it runs
    the following commands:
    - VACUUM: This command removes files that are no longer in use by Delta tables. It's important to run it to
    reduce storage costs.
    - OPTIMIZE (optional): This command rewrites the data in the Delta table to optimize its layout. It's important to run it to
    improve query performance.
    """

    def create_task(
        self,
        table_attributes: list,
        parallelism: int = 16,
        optimize_delta_table_local_id: int = None,
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        """
        Returns the task that optimizes all the Delta tables in the list.

        :param optimize_delta_table_local_id: This ID is used for adding a suffix to the task name since we can have multiple optmization tasks in the same DAG.
        """

        spark_job_name = f"optimize_delta_table"
        task_id = self.generate_task_id(table_attributes)
        if optimize_delta_table_local_id:
            task_id = f"{task_id}-{optimize_delta_table_local_id}"
        parameters = [
            table_attributes[0].layer.value,
            self._get_tables_parameter(table_attributes),
            parallelism,
        ]

        return self._create_spark_job_task(spark_job_name, task_id, parameters)

    def generate_task_id(self, tables_attributes: list = None) -> str:
        layer = tables_attributes[0].layer.value
        table_name = (
            tables_attributes[0].table_name if len(tables_attributes) == 1 else "all"
        )
        return StringFormatter.slugify(f"optimize-{layer}-{table_name}")

    def _get_tables_parameter(self, tables_attributes: list) -> str:
        default_vacuum_retention_hours = self.dag_execution_context.workflow_args.get(
            "vacuum_retention_hours", 48
        )
        default_run_optimize = self.dag_execution_context.workflow_args.get(
            "run_optimize", True
        )
        return json.dumps(
            {
                table.table_name: {
                    "schema": table.schema,
                    "vacuum_retention_hours": table.table_customization.get(
                        "vacuum_retention_hours", default_vacuum_retention_hours
                    ),
                    "run_optimize": table.table_customization.get(
                        "run_optimize", default_run_optimize
                    ),
                    "z_order_by": table.table_customization.get("z_order_by", []),
                }
                for table in tables_attributes
            }
        )
