import json
from typing import List, Optional, Tuple, Union

from airflow.models.baseoperator import BaseOperator
from airflow.utils.task_group import TaskGroup

from bietlejuice.base.airflow.optimize_delta_tables_cli import (
    encode_tables_json_for_emr_cli,
)
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.formatters.string_formatter import StringFormatter


def _chunk_table_attributes(table_attributes: List, batch_size: int) -> List[List]:
    if batch_size < 1:
        raise ValueError("batch_size must be at least 1")
    return [
        table_attributes[i : i + batch_size]
        for i in range(0, len(table_attributes), batch_size)
    ]


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
    ) -> Union[BaseOperator, TaskGroup]:
        """
        Returns the optimize dependency anchor for workflows.

        Single-task optimize returns that operator. When batching is enabled,
        returns a :class:`TaskGroup` so upstream ``load >> optimize`` wires to
        the first batch (roots) and downstream ``optimize >> sink`` wires from
        the last batch (leaves), with batches chained in between.
        """
        head, tail = self.create_optimize_tasks(
            table_attributes,
            parallelism=parallelism,
            optimize_delta_table_local_id=optimize_delta_table_local_id,
        )
        if head is tail:
            return head
        return head.task_group

    def create_optimize_tasks(
        self,
        table_attributes: list,
        parallelism: int = 16,
        optimize_delta_table_local_id: int = None,
    ) -> Tuple[BaseOperator, BaseOperator]:
        """
        Returns (first_optimize_task, last_optimize_task).

        By default, first and last are the same single task with all tables.

        When ``max_tables_per_optimize_tasks`` is set on ``workflow`` in the
        declaration, tables are split into batches on both Databricks and EMR,
        linked with ``batch_n >> batch_n+1`` so Airflow runs them strictly in order.

        ``optimize_parallelism`` on ``workflow`` overrides the caller ``parallelism``
        (driver ThreadPool size inside the optimize Spark job).
        """
        if not table_attributes:
            task = self._create_single_optimize_task(
                [],
                parallelism=parallelism,
                optimize_delta_table_local_id=optimize_delta_table_local_id,
                batch_index=None,
                num_batches=1,
            )
            return task, task

        parallelism = self._resolve_optimize_parallelism(parallelism)
        batch_size = self._max_tables_per_optimize_tasks()
        if batch_size is None:
            task = self._create_single_optimize_task(
                table_attributes,
                parallelism=parallelism,
                optimize_delta_table_local_id=optimize_delta_table_local_id,
                batch_index=None,
                num_batches=1,
            )
            return task, task

        chunks = _chunk_table_attributes(table_attributes, batch_size)
        num_batches = len(chunks)

        group_id = self._build_optimize_task_group_id(
            table_attributes, optimize_delta_table_local_id
        )
        with TaskGroup(
            group_id=group_id,
            dag=self.dag_execution_context.dag,
        ):
            tasks = [
                self._create_single_optimize_task(
                    chunk,
                    parallelism=parallelism,
                    optimize_delta_table_local_id=optimize_delta_table_local_id,
                    batch_index=batch_index if num_batches > 1 else None,
                    num_batches=num_batches,
                )
                for batch_index, chunk in enumerate(chunks, start=1)
            ]
            _chain_optimize_tasks_sequentially(tasks)
        return tasks[0], tasks[-1]

    def _max_tables_per_optimize_tasks(self) -> Optional[int]:
        value = self.dag_execution_context.workflow_args.get(
            "max_tables_per_optimize_tasks"
        )
        if value is None:
            return None
        return int(value)

    def _resolve_optimize_parallelism(self, parallelism: int) -> int:
        value = self.dag_execution_context.workflow_args.get("optimize_parallelism")
        if value is None:
            return parallelism
        return int(value)

    def _create_single_optimize_task(
        self,
        table_attributes: list,
        parallelism: int,
        optimize_delta_table_local_id: Optional[int],
        batch_index: Optional[int],
        num_batches: int,
    ) -> BaseOperator:
        spark_job_name = "optimize_delta_table"
        task_id = self._build_task_id(
            table_attributes,
            optimize_delta_table_local_id,
            batch_index,
            num_batches,
        )
        tables_config = self._build_tables_config(table_attributes)
        tables_json = json.dumps(tables_config, separators=(",", ":"))
        if self.dag_execution_context.use_airflow_emr:
            tables_json = encode_tables_json_for_emr_cli(tables_json)
        layer_value = table_attributes[0].layer.value if table_attributes else "raw"
        parameters = [
            layer_value,
            tables_json,
            parallelism,
        ]
        if any(cfg.get("apply_partition_filter") for cfg in tables_config.values()):
            parameters += [
                "--load-start-date",
                self.dag_execution_context.load_start_date,
                "--load-end-date",
                self.dag_execution_context.load_end_date,
            ]
        return self._create_spark_job_task(spark_job_name, task_id, parameters)

    def _build_optimize_task_group_id(
        self,
        table_attributes: list,
        optimize_delta_table_local_id: Optional[int],
    ) -> str:
        task_id = self._build_task_id(
            table_attributes,
            optimize_delta_table_local_id,
            batch_index=None,
            num_batches=1,
        )
        return f"{task_id}-batches"

    def _build_task_id(
        self,
        tables_attributes: list,
        optimize_delta_table_local_id: Optional[int],
        batch_index: Optional[int],
        num_batches: int,
    ) -> str:
        if tables_attributes:
            task_id = self.generate_task_id(tables_attributes)
        else:
            task_id = StringFormatter.slugify("optimize-empty")
        if num_batches > 1 and batch_index is not None:
            task_id = f"{task_id}-batch-{batch_index}"
        if optimize_delta_table_local_id:
            task_id = f"{task_id}-{optimize_delta_table_local_id}"
        return task_id

    def generate_task_id(self, tables_attributes: list = None) -> str:
        layer = tables_attributes[0].layer.value
        table_name = (
            tables_attributes[0].table_name if len(tables_attributes) == 1 else "all"
        )
        return StringFormatter.slugify(f"optimize-{layer}-{table_name}")

    def _build_tables_config(self, tables_attributes: list) -> dict:
        default_vacuum_retention_hours = self.dag_execution_context.workflow_args.get(
            "vacuum_retention_hours", 48
        )
        default_run_optimize = self.dag_execution_context.workflow_args.get(
            "run_optimize", True
        )
        default_run_vacuum = self.dag_execution_context.workflow_args.get(
            "run_vacuum", True
        )
        default_vacuum_lite = self.dag_execution_context.workflow_args.get(
            "vacuum_lite", False
        )

        tables_config = {}
        for table in tables_attributes:
            default_z_order_by = table.table_customization.get("z_order_by", [])

            if table.layer in (LayerEnum.TRANSACTIONAL, LayerEnum.RAW):
                z_order_by = table.table_customization.get(
                    "raw_z_order_by", default_z_order_by
                )
            elif table.layer == LayerEnum.CLEAN:
                z_order_by = table.table_customization.get(
                    "clean_z_order_by", default_z_order_by
                )
            else:
                z_order_by = default_z_order_by

            table_config = {
                "schema": table.schema,
                "vacuum_retention_hours": table.table_customization.get(
                    "vacuum_retention_hours", default_vacuum_retention_hours
                ),
                "run_optimize": table.table_customization.get(
                    "run_optimize", default_run_optimize
                ),
                "run_vacuum": table.table_customization.get(
                    "run_vacuum", default_run_vacuum
                ),
                "vacuum_lite": table.table_customization.get(
                    "vacuum_lite", default_vacuum_lite
                ),
                "z_order_by": z_order_by,
            }
            if table.layer == LayerEnum.TRANSACTIONAL:
                table_config["apply_partition_filter"] = table.table_customization.get(
                    "optimize_partition_filter", True
                )
            tables_config[table.table_name] = table_config

        return tables_config


def _chain_optimize_tasks_sequentially(tasks: List[BaseOperator]) -> None:
    """
    Airflow task dependency chain: batch i+1 cannot start until batch i succeeds.

    This is the only ordering guarantee (not EMR step concurrency inside the cluster).
    """
    for previous, current in zip(tasks, tasks[1:]):
        previous >> current
