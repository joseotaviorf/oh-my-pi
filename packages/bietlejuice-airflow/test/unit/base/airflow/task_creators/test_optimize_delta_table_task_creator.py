from unittest.mock import patch

import pytest
from airflow.models import DAG
from airflow.operators.empty import EmptyOperator
from airflow.utils.task_group import TaskGroup

from bietlejuice.base.airflow.optimize_delta_tables_cli import (
    decode_tables_config_from_cli,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.optimize_delta_table_task_creator import (
    OptimizeDeltaTableTaskCreator,
    _chain_optimize_tasks_sequentially,
    _chunk_table_attributes,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.environment_enum import EnvironmentEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum

TEST_MAINTENANCE_DATE = "2026-05-28"


def _load_date_cli_args(parameters: list) -> list:
    if "--load-start-date" not in parameters:
        return []
    start = parameters.index("--load-start-date")
    end = parameters.index("--load-end-date") + 2
    return parameters[start:end]


def _maintenance_cli_args(parameters: list) -> list:
    return parameters[parameters.index("--environment") :]


def _table(name: str, layer: LayerEnum = LayerEnum.RAW) -> TableAttributes:
    return TableAttributes(
        dag_args={"name": "test_dag"},
        workflow_args={"custom_schema": "my_schema"},
        layer=layer,
        table_name=name,
    )


@pytest.fixture
def dag_execution_context():
    dag = DAG(dag_id="test_dag", schedule=None)
    return DagExecutionContext(
        dag=dag,
        environment=EnvironmentEnum.FORNO,
        bucket="test-bucket",
        base_spark_jobs_path="/dags/cross/base/spark_jobs",
        dag_args={"name": "test_dag"},
        workflow_args={},
        cluster_args={"type": "emr_preset"},
    )


class TestChunkTableAttributes:
    def test_chunks_by_batch_size(self):
        items = list(range(13))
        chunks = _chunk_table_attributes(items, 5)
        assert chunks == [list(range(5)), list(range(5, 10)), list(range(10, 13))]

    def test_rejects_invalid_batch_size(self):
        with pytest.raises(ValueError, match="batch_size"):
            _chunk_table_attributes([], 0)


class TestOptimizeDeltaTableTaskCreator:
    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_databricks_returns_single_task_head_equals_tail(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = False
        mock_create_spark.side_effect = lambda *a, **k: EmptyOperator(
            task_id=k.get("task_id", a[1]), dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        tables = [_table("t1"), _table("t2")]
        head, tail = creator.create_optimize_tasks(tables, parallelism=16)

        assert head is tail
        mock_create_spark.assert_called_once()
        assert mock_create_spark.call_args[0][2][2] == 16

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_databricks_splits_into_chained_batches_when_workflow_key_set(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = False
        dag_execution_context.workflow_args["max_tables_per_optimize_tasks"] = 2
        task_ids = []

        def make_op(spark_job_name, task_id, parameters):
            task_ids.append(task_id)
            return EmptyOperator(task_id=task_id, dag=dag_execution_context.dag)

        mock_create_spark.side_effect = make_op

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        tables = [_table("a"), _table("b"), _table("c")]
        head, tail = creator.create_optimize_tasks(tables, parallelism=16)

        assert mock_create_spark.call_count == 2
        assert len(task_ids) == 2
        assert "batch-1" in head.task_id
        assert "batch-2" in tail.task_id
        assert head.downstream_list == [tail]
        assert tail.upstream_list == [head]
        assert isinstance(head.task_group, TaskGroup)
        assert head.task_group.group_id.endswith("-batches")

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_create_task_returns_task_group_when_batched(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = False
        dag_execution_context.workflow_args["max_tables_per_optimize_tasks"] = 2
        task_ids = []

        def make_op(spark_job_name, task_id, parameters):
            task_ids.append(task_id)
            return EmptyOperator(task_id=task_id, dag=dag_execution_context.dag)

        mock_create_spark.side_effect = make_op

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        tables = [_table("a"), _table("b"), _table("c")]
        optimize_anchor = creator.create_task(tables, parallelism=16)

        assert isinstance(optimize_anchor, TaskGroup)
        load = EmptyOperator(task_id="load", dag=dag_execution_context.dag)
        sink = EmptyOperator(task_id="sink", dag=dag_execution_context.dag)
        load >> optimize_anchor >> sink

        head = optimize_anchor.roots[0]
        tail = optimize_anchor.leaves[0]
        assert head.upstream_list == [load]
        assert tail.downstream_list == [sink]
        assert head.downstream_list == [tail]
        assert tail.upstream_list == [head]

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_create_task_returns_single_operator_without_batching(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = False
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        optimize_anchor = creator.create_task([_table("t1")])

        assert isinstance(optimize_anchor, EmptyOperator)
        assert not isinstance(optimize_anchor, TaskGroup)

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_splits_into_chained_batches(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        dag_execution_context.workflow_args["max_tables_per_optimize_tasks"] = 2
        task_ids = []

        def make_op(spark_job_name, task_id, parameters):
            task_ids.append(task_id)
            return EmptyOperator(task_id=task_id, dag=dag_execution_context.dag)

        mock_create_spark.side_effect = make_op

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        tables = [_table("a"), _table("b"), _table("c")]
        head, tail = creator.create_optimize_tasks(tables, parallelism=16)

        assert mock_create_spark.call_count == 2
        assert len(task_ids) == 2
        assert "batch-1" in head.task_id
        assert "batch-2" in tail.task_id
        assert mock_create_spark.call_args_list[0][0][2][2] == 16
        assert mock_create_spark.call_args_list[1][0][2][2] == 16
        assert head.downstream_list == [tail]
        assert tail.upstream_list == [head]
        assert isinstance(head.task_group, TaskGroup)

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_without_batch_config_returns_single_task(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        tables = [_table("a"), _table("b"), _table("c")]
        head, tail = creator.create_optimize_tasks(tables, parallelism=16)

        assert head is tail
        mock_create_spark.assert_called_once()
        assert mock_create_spark.call_args[0][2][2] == 16

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_single_batch_no_batch_suffix(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        dag_execution_context.workflow_args["max_tables_per_optimize_tasks"] = 10
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        head, tail = creator.create_optimize_tasks([_table("only")])

        assert head is tail
        assert "batch" not in head.task_id
        mock_create_spark.assert_called_once()

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_encodes_tables_json_for_cli(
        self, mock_create_spark, dag_execution_context
    ):
        from bietlejuice.base.airflow.optimize_delta_tables_cli import (
            EMR_TABLES_B64_PREFIX,
        )

        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1")])

        tables_param = mock_create_spark.call_args[0][2][1]
        assert tables_param.startswith(EMR_TABLES_B64_PREFIX)

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_uses_workflow_parallelism_override(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        dag_execution_context.workflow_args["optimize_parallelism"] = 4
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-clean-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1", LayerEnum.CLEAN)], parallelism=16)

        assert mock_create_spark.call_args[0][2][2] == 4

    def test_chain_optimize_tasks_sequentially_links_in_order(
        self, dag_execution_context
    ):
        ops = [
            EmptyOperator(task_id=f"batch-{i}", dag=dag_execution_context.dag)
            for i in range(1, 4)
        ]
        _chain_optimize_tasks_sequentially(ops)
        assert ops[0].downstream_list == [ops[1]]
        assert ops[1].downstream_list == [ops[2]]
        assert ops[2].downstream_list == []


class TestPartitionFilterWiring:
    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_transactional_layer_sets_partition_filter_and_date_args(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        dag_execution_context.load_start_date = "{{ load_start }}"
        dag_execution_context.load_end_date = "{{ load_end }}"
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-transactional-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1", LayerEnum.TRANSACTIONAL)])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert tables_config["t1"]["apply_partition_filter"] is True
        assert _load_date_cli_args(parameters) == [
            "--load-start-date",
            "{{ load_start }}",
            "--load-end-date",
            "{{ load_end }}",
        ]

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_raw_layer_does_not_set_partition_filter_or_date_args(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1", LayerEnum.RAW)])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert "apply_partition_filter" not in tables_config["t1"]
        assert "--load-start-date" not in parameters

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_clean_layer_does_not_set_partition_filter_or_date_args(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-clean-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1", LayerEnum.CLEAN)])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert "apply_partition_filter" not in tables_config["t1"]
        assert "--load-start-date" not in parameters

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_transactional_opt_out_disables_partition_filter_and_skips_date_args(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-transactional-all", dag=dag_execution_context.dag
        )
        table = TableAttributes(
            dag_args={"name": "test_dag"},
            workflow_args={
                "custom_schema": "my_schema",
                "tables_customization": {"t1": {"optimize_partition_filter": False}},
            },
            layer=LayerEnum.TRANSACTIONAL,
            table_name="t1",
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert tables_config["t1"]["apply_partition_filter"] is False
        assert "--load-start-date" not in parameters

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_raw_layer_with_workflow_incremental_optimize_sets_partition_filter(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        dag_execution_context.load_start_date = "{{ load_start }}"
        dag_execution_context.load_end_date = "{{ load_end }}"
        dag_execution_context.workflow_args["incremental_optimize"] = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-all", dag=dag_execution_context.dag
        )
        table = TableAttributes(
            dag_args={"name": "test_dag"},
            workflow_args={
                "custom_schema": "my_schema",
                "incremental_optimize": True,
            },
            layer=LayerEnum.RAW,
            table_name="t1",
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert tables_config["t1"]["apply_partition_filter"] is True
        assert _load_date_cli_args(parameters) == [
            "--load-start-date",
            "{{ load_start }}",
            "--load-end-date",
            "{{ load_end }}",
        ]

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_clean_layer_table_override_enables_partition_filter(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        dag_execution_context.load_start_date = "{{ load_start }}"
        dag_execution_context.load_end_date = "{{ load_end }}"
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-clean-all", dag=dag_execution_context.dag
        )
        table = TableAttributes(
            dag_args={"name": "test_dag"},
            workflow_args={
                "custom_schema": "my_schema",
                "incremental_optimize": False,
                "tables_customization": {"t1": {"incremental_optimize": True}},
            },
            layer=LayerEnum.CLEAN,
            table_name="t1",
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert tables_config["t1"]["apply_partition_filter"] is True
        assert _load_date_cli_args(parameters)

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_raw_layer_table_override_disables_workflow_default(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        dag_execution_context.workflow_args["incremental_optimize"] = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-all", dag=dag_execution_context.dag
        )
        table = TableAttributes(
            dag_args={"name": "test_dag"},
            workflow_args={
                "custom_schema": "my_schema",
                "incremental_optimize": True,
                "tables_customization": {"t1": {"incremental_optimize": False}},
            },
            layer=LayerEnum.RAW,
            table_name="t1",
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert "apply_partition_filter" not in tables_config["t1"]
        assert "--load-start-date" not in parameters

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_transactional_default_unchanged_when_workflow_incremental_optimize_false(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        dag_execution_context.use_airflow_emr = False
        dag_execution_context.load_start_date = "{{ load_start }}"
        dag_execution_context.load_end_date = "{{ load_end }}"
        dag_execution_context.workflow_args["incremental_optimize"] = False
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-transactional-all", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1", LayerEnum.TRANSACTIONAL)])

        parameters = mock_create_spark.call_args[0][2]
        tables_config = json.loads(parameters[1])
        assert tables_config["t1"]["apply_partition_filter"] is True
        assert _load_date_cli_args(parameters)


class TestMaintenanceStateWiring:
    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_tables_config_defaults_maintenance_once_per_day_true(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        # arrange
        dag_execution_context.use_airflow_emr = False
        dag_execution_context.execution_date = TEST_MAINTENANCE_DATE
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )
        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)

        # act
        creator.create_optimize_tasks([_table("t1")])
        tables_config = json.loads(mock_create_spark.call_args[0][2][1])

        # assert
        assert tables_config["t1"]["maintenance_once_per_day"] is True

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_workflow_can_disable_maintenance_once_per_day(
        self, mock_create_spark, dag_execution_context
    ):
        import json

        # arrange
        dag_execution_context.use_airflow_emr = False
        dag_execution_context.workflow_args["maintenance_once_per_day"] = False
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )
        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)

        # act
        creator.create_optimize_tasks([_table("t1")])
        tables_config = json.loads(mock_create_spark.call_args[0][2][1])

        # assert
        assert tables_config["t1"]["maintenance_once_per_day"] is False

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_passes_maintenance_cli_args_without_state_bucket(
        self, mock_create_spark, dag_execution_context
    ):
        # arrange
        dag_execution_context.use_airflow_emr = False
        dag_execution_context.execution_date = TEST_MAINTENANCE_DATE
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )
        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        dag_name = dag_execution_context.dag_args["name"]

        # act
        creator.create_optimize_tasks([_table("t1")])
        parameters = mock_create_spark.call_args[0][2]

        # assert
        assert _maintenance_cli_args(parameters) == [
            "--environment",
            dag_execution_context.environment,
            "--dag-name",
            dag_name,
            "--maintenance-date",
            dag_execution_context.execution_date,
        ]
        assert "--state-bucket" not in parameters


def _table_with_zorder(
    name: str,
    z_order_by: list,
    layer: LayerEnum = LayerEnum.ENRICH,
    zorder_key: str = "z_order_by",
    extra_customization: dict = None,
) -> TableAttributes:
    customization = {zorder_key: z_order_by}
    if extra_customization:
        customization.update(extra_customization)
    return TableAttributes(
        dag_args={"name": "test_dag"},
        workflow_args={
            "custom_schema": "my_schema",
            "tables_customization": {name: customization},
        },
        layer=layer,
        table_name=name,
    )


class TestEngineAwareOptimizeDefaults:
    """EMR defaults OPTIMIZE off unless zorder is configured (then weekly); Databricks unchanged."""

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_databricks_no_zorder_defaults_optimize_on_daily(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = False
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1")])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 1

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_no_zorder_defaults_optimize_off(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1")])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is False
        assert tables_config["t1"]["optimize_frequency_days"] == 1

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_zorder_defaults_optimize_on_weekly(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-enrich-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder("t1", ["user_id"])

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 7

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_raw_zorder_defaults_optimize_on_weekly(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder(
            "t1", ["user_id"], layer=LayerEnum.RAW, zorder_key="raw_z_order_by"
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 7

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_no_zorder_explicit_run_optimize_true_keeps_daily_frequency(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )
        table = TableAttributes(
            dag_args={"name": "test_dag"},
            workflow_args={
                "custom_schema": "my_schema",
                "tables_customization": {"t1": {"run_optimize": True}},
            },
            layer=LayerEnum.RAW,
            table_name="t1",
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 1

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_zorder_explicit_run_optimize_false_overrides_default(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-enrich-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder(
            "t1", ["user_id"], extra_customization={"run_optimize": False}
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is False

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_zorder_explicit_frequency_override_wins(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-enrich-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder(
            "t1", ["user_id"], extra_customization={"optimize_frequency_days": 3}
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 3

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_workflow_level_run_optimize_override_applies_to_all_tables(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        dag_execution_context.workflow_args["run_optimize"] = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-raw-t1", dag=dag_execution_context.dag
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([_table("t1")])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_workflow_level_optimize_frequency_days_override_applies_to_all_tables(
        self, mock_create_spark, dag_execution_context
    ):
        dag_execution_context.use_airflow_emr = True
        dag_execution_context.workflow_args["optimize_frequency_days"] = 14
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-enrich-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder("t1", ["user_id"])

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["optimize_frequency_days"] == 14

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_zorder_transactional_layer_keeps_daily_frequency(
        self, mock_create_spark, dag_execution_context
    ):
        """TRANSACTIONAL tables are partition-filtered by default: OPTIMIZE's WHERE
        clause only ever covers the current run's date range, so a weekly cadence
        would leave 6 of every 7 days' partitions permanently un-optimized. ZORDER
        still turns OPTIMIZE on, but frequency must stay daily."""
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-transactional-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder(
            "t1",
            ["user_id"],
            layer=LayerEnum.TRANSACTIONAL,
            zorder_key="raw_z_order_by",
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["apply_partition_filter"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 1

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_zorder_transactional_opt_out_reverts_to_weekly_frequency(
        self, mock_create_spark, dag_execution_context
    ):
        """When a TRANSACTIONAL table opts out of the partition filter
        (``optimize_partition_filter: False``), OPTIMIZE runs full-table again, so
        the weekly cadence is safe and applies as usual."""
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-transactional-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder(
            "t1",
            ["user_id"],
            layer=LayerEnum.TRANSACTIONAL,
            zorder_key="raw_z_order_by",
            extra_customization={"optimize_partition_filter": False},
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["apply_partition_filter"] is False
        assert tables_config["t1"]["optimize_frequency_days"] == 7

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_zorder_incremental_optimize_table_override_keeps_daily_frequency(
        self, mock_create_spark, dag_execution_context
    ):
        """A non-TRANSACTIONAL table that opts into incremental_optimize is also
        partition-filtered, so it must keep the daily cadence despite ZORDER."""
        dag_execution_context.use_airflow_emr = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-clean-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder(
            "t1",
            ["user_id"],
            layer=LayerEnum.CLEAN,
            zorder_key="clean_z_order_by",
            extra_customization={"incremental_optimize": True},
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["apply_partition_filter"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 1

    @patch.object(OptimizeDeltaTableTaskCreator, "_create_spark_job_task")
    def test_emr_with_zorder_workflow_incremental_optimize_keeps_daily_frequency(
        self, mock_create_spark, dag_execution_context
    ):
        """Same as above, but incremental_optimize is set at the workflow level
        rather than per-table."""
        dag_execution_context.use_airflow_emr = True
        dag_execution_context.workflow_args["incremental_optimize"] = True
        mock_create_spark.return_value = EmptyOperator(
            task_id="optimize-clean-t1", dag=dag_execution_context.dag
        )
        table = _table_with_zorder(
            "t1", ["user_id"], layer=LayerEnum.CLEAN, zorder_key="clean_z_order_by"
        )

        creator = OptimizeDeltaTableTaskCreator(dag_execution_context)
        creator.create_optimize_tasks([table])
        tables_config = decode_tables_config_from_cli(
            mock_create_spark.call_args[0][2][1]
        )

        assert tables_config["t1"]["run_optimize"] is True
        assert tables_config["t1"]["apply_partition_filter"] is True
        assert tables_config["t1"]["optimize_frequency_days"] == 1
