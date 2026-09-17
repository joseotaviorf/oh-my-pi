import json
from os import path
from typing import Callable, List, Optional, Tuple, Union

from airflow.models.baseoperator import BaseOperator
from airflow.utils.task_group import TaskGroup

from bietlejuice.base.airflow.optimize_delta_tables_cli import (
    assert_optimize_batches_partition_tables,
    build_and_validate_emr_tables_cli_arg,
    chunk_table_attributes_for_emr_limit,
    make_optimize_emr_step_validator,
)
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.db.datalake_metastore_mapping import require_transformation_grade
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.formatters.string_formatter import StringFormatter
from bietlejuice.services.configuration_service import ConfigurationService

# Rendered by Airflow at task runtime, so the `vacuum_lite_watermark_enabled` Airflow
# Variable can be toggled from the UI without a deploy. Read as a template rather than
# via Variable.get() so the scheduler does not hit the metadata DB on every DAG parse.
# The spark job treats anything other than 'true' as disabled, so an unset Variable or
# an unrendered template is fail-safe.
_VACUUM_LITE_WATERMARK_TEMPLATE = (
    "{{ var.value.get('vacuum_lite_watermark_enabled', 'false') }}"
)


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

    On EMR, table configs are base64-encoded into a single spark-submit arg. AWS
    AddJobFlowSteps limits the total of all ``HadoopJarStep`` string values to
    10,240 (and each field to 10,280). Optimize auto-batches when the full
    spark-submit step (prefix + tables B64 + job params) would exceed that
    budget — not only when the tables arg alone is too large. Override with
    ``workflow.max_tables_per_optimize_tasks``. Each batch is validated at DAG
    parse time (full-step fit + round-trip decode).
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

        On EMR, when that key is unset and the encoded tables config would exceed the
        AWS arg limit, batch size is computed automatically with the same chaining.

        ``optimize_parallelism`` on ``workflow`` overrides the caller ``parallelism``
        (ThreadPool size inside the optimize Spark job; S3 markers are written on the
        main thread after each table completes).
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
        chunks = self._resolve_optimize_chunks(
            table_attributes,
            parallelism=parallelism,
            optimize_delta_table_local_id=optimize_delta_table_local_id,
        )
        if self.dag_execution_context.use_airflow_emr:
            assert_optimize_batches_partition_tables(table_attributes, chunks)

        num_batches = len(chunks)
        if num_batches == 1:
            task = self._create_single_optimize_task(
                table_attributes,
                parallelism=parallelism,
                optimize_delta_table_local_id=optimize_delta_table_local_id,
                batch_index=None,
                num_batches=1,
            )
            return task, task

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
                    batch_index=batch_index,
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

    def _resolve_optimize_chunks(
        self,
        table_attributes: list,
        *,
        parallelism: int,
        optimize_delta_table_local_id: Optional[int],
    ) -> List[List]:
        explicit_batch_size = self._max_tables_per_optimize_tasks()
        validate_step_fit = self._make_emr_optimize_step_validator(
            table_attributes=table_attributes,
            parallelism=parallelism,
            optimize_delta_table_local_id=optimize_delta_table_local_id,
        )
        if explicit_batch_size is not None:
            chunks = _chunk_table_attributes(table_attributes, explicit_batch_size)
            if self.dag_execution_context.use_airflow_emr:
                for chunk in chunks:
                    build_and_validate_emr_tables_cli_arg(
                        self._build_tables_config(chunk),
                        validate_step_fit=validate_step_fit,
                    )
            return chunks
        if self.dag_execution_context.use_airflow_emr:
            return chunk_table_attributes_for_emr_limit(
                table_attributes,
                self._build_tables_config,
                validate_step_fit,
            )
        return [table_attributes]

    def _resolve_optimize_parallelism(self, parallelism: int) -> int:
        value = self.dag_execution_context.workflow_args.get("optimize_parallelism")
        if value is None:
            return parallelism
        return int(value)

    def _worst_case_emr_optimize_task_id(
        self,
        table_attributes: list,
        optimize_delta_table_local_id: Optional[int],
    ) -> str:
        """Longest task id any optimize batch may emit (OpenLineage parentJobName budget)."""
        if not table_attributes:
            return self._build_task_id(
                [], optimize_delta_table_local_id, batch_index=None, num_batches=1
            )

        layer = table_attributes[0].layer.value
        max_batch_index = len(table_attributes)
        slug_bases = [
            StringFormatter.slugify(f"optimize-{layer}-all"),
            *(
                StringFormatter.slugify(f"optimize-{layer}-{table.table_name}")
                for table in table_attributes
            ),
        ]
        longest_base = max(slug_bases, key=len)
        task_id = f"{longest_base}-batch-{max_batch_index}"
        if optimize_delta_table_local_id:
            task_id = f"{task_id}-{optimize_delta_table_local_id}"
        return task_id

    def _make_emr_optimize_step_validator(
        self,
        *,
        table_attributes: list,
        parallelism: int,
        optimize_delta_table_local_id: Optional[int],
        task_id: Optional[str] = None,
    ) -> Callable[[str], None]:
        """Build a validator for the full optimize EMR HadoopJarStep (not tables-only)."""
        tables_config = self._build_tables_config(table_attributes)
        include_load_dates = any(
            cfg.get("apply_partition_filter") for cfg in tables_config.values()
        )
        layer_value = table_attributes[0].layer.value if table_attributes else "raw"
        budget_task_id = task_id or self._worst_case_emr_optimize_task_id(
            table_attributes, optimize_delta_table_local_id
        )
        spark_job_path = path.join(
            self.dag_execution_context.base_spark_jobs_path,
            "optimize_delta_table.py",
        )
        return make_optimize_emr_step_validator(
            script_uri=spark_job_path,
            layer_value=layer_value,
            parallelism=parallelism,
            include_load_dates=include_load_dates,
            load_start_date=self.dag_execution_context.load_start_date,
            load_end_date=self.dag_execution_context.load_end_date,
            maintenance_cli_args=self._build_maintenance_state_cli_args(),
            task_id=budget_task_id,
            dag_id=self.dag_execution_context.dag.dag_id,
        )

    def _build_optimize_job_parameters(
        self,
        *,
        layer_value: str,
        tables_json: str,
        parallelism: int,
        include_load_dates: bool,
    ) -> list:
        parameters = [layer_value, tables_json, parallelism]
        if include_load_dates:
            parameters += [
                "--load-start-date",
                self.dag_execution_context.load_start_date,
                "--load-end-date",
                self.dag_execution_context.load_end_date,
            ]
        parameters += [
            "--vacuum-lite-watermark",
            _VACUUM_LITE_WATERMARK_TEMPLATE,
        ]
        parameters += self._build_maintenance_state_cli_args()
        return parameters

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
        include_load_dates = any(
            cfg.get("apply_partition_filter") for cfg in tables_config.values()
        )
        layer_value = table_attributes[0].layer.value if table_attributes else "raw"
        if self.dag_execution_context.use_airflow_emr:
            validate_step_fit = self._make_emr_optimize_step_validator(
                table_attributes=table_attributes,
                parallelism=parallelism,
                optimize_delta_table_local_id=optimize_delta_table_local_id,
                task_id=task_id,
            )
            tables_json = build_and_validate_emr_tables_cli_arg(
                tables_config,
                validate_step_fit=validate_step_fit,
            )
        else:
            tables_json = json.dumps(tables_config, separators=(",", ":"))
        parameters = self._build_optimize_job_parameters(
            layer_value=layer_value,
            tables_json=tables_json,
            parallelism=parallelism,
            include_load_dates=include_load_dates,
        )
        return self._create_spark_job_task(spark_job_name, task_id, parameters)

    def _build_maintenance_state_cli_args(self) -> list:
        dag_name = self.dag_execution_context.dag_args["name"]
        config_service = ConfigurationService(dag_name)
        config_prefix = config_service.get_config("delta_maintenance_state_prefix")
        state_prefix = self.dag_execution_context.workflow_args.get(
            "maintenance_state_prefix", config_prefix
        )
        args = [
            "--environment",
            self.dag_execution_context.environment,
            "--dag-name",
            dag_name,
            "--maintenance-date",
            self.dag_execution_context.execution_date,
        ]
        if state_prefix != config_prefix:
            args += ["--state-prefix", state_prefix]
        return args

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
        default_run_vacuum = self.dag_execution_context.workflow_args.get(
            "run_vacuum", True
        )
        default_vacuum_lite = self.dag_execution_context.workflow_args.get(
            "vacuum_lite", True
        )
        default_maintenance_once_per_day = self.dag_execution_context.workflow_args.get(
            "maintenance_once_per_day", True
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

            apply_partition_filter = self._resolve_apply_partition_filter(table)

            run_optimize, optimize_frequency_days = (
                self._resolve_run_optimize_and_frequency(
                    table, z_order_by, apply_partition_filter
                )
            )

            table_config = {
                "schema": table.schema,
                "vacuum_retention_hours": table.table_customization.get(
                    "vacuum_retention_hours", default_vacuum_retention_hours
                ),
                "run_optimize": run_optimize,
                "optimize_frequency_days": optimize_frequency_days,
                "run_vacuum": table.table_customization.get(
                    "run_vacuum", default_run_vacuum
                ),
                "vacuum_lite": table.table_customization.get(
                    "vacuum_lite", default_vacuum_lite
                ),
                "maintenance_once_per_day": table.table_customization.get(
                    "maintenance_once_per_day", default_maintenance_once_per_day
                ),
                "z_order_by": z_order_by,
            }
            if table.layer == LayerEnum.TRANSACTIONAL:
                table_config["apply_partition_filter"] = apply_partition_filter
            elif apply_partition_filter:
                table_config["apply_partition_filter"] = True
            if table.layer == LayerEnum.TRANSFORMATION:
                table_config["transformation_grade"] = require_transformation_grade(
                    table.transformation_grade
                )
            tables_config[table.table_name] = table_config

        return tables_config

    def _resolve_apply_partition_filter(self, table) -> bool:
        """Resolve whether OPTIMIZE will be scoped to the run's date range.

        ``True`` for TRANSACTIONAL-layer tables by default (``optimize_partition_filter``
        opts out), and for any other table with ``incremental_optimize`` enabled
        (table-level, else workflow-level). Mirrors the table-config key of the
        same purpose consumed by the Spark job (``run_job`` in
        ``optimize_delta_table.py``), computed here first so the OPTIMIZE cadence
        default can take it into account.
        """
        if table.layer == LayerEnum.TRANSACTIONAL:
            return table.table_customization.get("optimize_partition_filter", True)
        workflow_incremental_optimize = self.dag_execution_context.workflow_args.get(
            "incremental_optimize", False
        )
        return bool(
            table.table_customization.get(
                "incremental_optimize", workflow_incremental_optimize
            )
        )

    def _resolve_run_optimize_and_frequency(
        self, table, z_order_by: list, apply_partition_filter: bool
    ) -> Tuple[bool, int]:
        """Resolve ``run_optimize`` + ``optimize_frequency_days``, engine- and zorder-aware.

        Explicit ``run_optimize``/``optimize_frequency_days`` (table-level, else
        workflow-level) always win — no behavior change for declarations that
        already set them.

        Absent any explicit config: Databricks keeps the historical default
        (optimize on, capped once per day). EMR defaults optimize *off*, since
        ``OPTIMIZE`` is a full shuffle/compaction and is proportionally far more
        expensive on Delta OSS/EMR than on Databricks — unless the table has
        ZORDER columns configured, in which case it defaults *on*.

        The weekly cadence (``optimize_frequency_days=7``) only applies when
        OPTIMIZE runs full-table (``apply_partition_filter`` is False): OPTIMIZE's
        ``WHERE`` clause is scoped to the *current run's* date range only (see
        ``_resolve_partition_predicate`` in ``optimize_delta_table.py``), never to
        the days elapsed since the last actual OPTIMIZE. So when
        ``apply_partition_filter`` is True (TRANSACTIONAL tables by default, or any
        table with ``incremental_optimize``), a weekly cadence would leave 6 of
        every 7 days' partitions permanently un-optimized — that OPTIMIZE is
        already cheap (bounded to the run's date range), so it stays daily
        regardless of ZORDER.
        """
        workflow_args = self.dag_execution_context.workflow_args
        table_customization = table.table_customization
        use_emr = self.dag_execution_context.use_airflow_emr
        has_zorder = bool(z_order_by)

        if "run_optimize" in table_customization:
            run_optimize = table_customization["run_optimize"]
        elif "run_optimize" in workflow_args:
            run_optimize = workflow_args["run_optimize"]
        elif use_emr:
            run_optimize = has_zorder
        else:
            run_optimize = True

        default_frequency_days = (
            7 if (use_emr and has_zorder and not apply_partition_filter) else 1
        )
        optimize_frequency_days = table_customization.get(
            "optimize_frequency_days",
            workflow_args.get("optimize_frequency_days", default_frequency_days),
        )
        return run_optimize, int(optimize_frequency_days)


def _chain_optimize_tasks_sequentially(tasks: List[BaseOperator]) -> None:
    """
    Airflow task dependency chain: batch i+1 cannot start until batch i succeeds.

    This is the only ordering guarantee (not EMR step concurrency inside the cluster).
    """
    for previous, current in zip(tasks, tasks[1:]):
        previous >> current
