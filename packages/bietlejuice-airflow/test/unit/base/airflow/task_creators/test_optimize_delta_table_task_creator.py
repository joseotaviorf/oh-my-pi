from unittest.mock import patch

import pytest
from airflow.models import DAG
from airflow.operators.empty import EmptyOperator
from airflow.utils.task_group import TaskGroup

from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.optimize_delta_table_task_creator import (
    OptimizeDeltaTableTaskCreator,
    _chain_optimize_tasks_sequentially,
    _chunk_table_attributes,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


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
        environment="forno",
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
        assert parameters[3:] == [
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
