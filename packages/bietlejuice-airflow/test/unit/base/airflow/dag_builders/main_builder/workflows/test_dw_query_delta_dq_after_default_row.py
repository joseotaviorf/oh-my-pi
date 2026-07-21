"""Opt-in serialize_dq_after_default_row for query_delta DW dims."""

from datetime import datetime
from unittest.mock import MagicMock, patch

from airflow.models.dag import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_delta_workflow import (
    DwQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestDwQueryDeltaDqAfterDefaultRow:
    def _workflow(self, **workflow_overrides) -> DwQueryDeltaWorkflow:
        workflow_args = {
            "type": "query_delta",
            "layer": "dw",
            "custom_schema": "employee",
            "default_extraction_type": "full",
            "has_hive_sync": False,
            **workflow_overrides,
        }
        with patch.dict("os.environ", {"ENVIRONMENT": "forno"}):
            workflow = DwQueryDeltaWorkflow(
                {"name": "dw_employee", "owner": "Data People"},
                workflow_args,
                {
                    "type": "consolidation_m_general_cluster",
                    "databricks_conn_id": "databricks_new_env",
                },
            )
        workflow.config_service = MagicMock()
        return workflow

    def _bind_creators(self, workflow: DwQueryDeltaWorkflow, dag: DAG) -> None:
        def _op(task_id: str):
            return EmptyOperator(task_id=task_id, dag=dag)

        workflow.load_dw_task_creator = MagicMock(
            create_task=lambda table: _op(f"load-dw-{table.table_name}")
        )
        workflow.load_custom_task_creator = MagicMock(
            create_task=lambda table: _op(f"load-custom-{table.table_name}")
        )
        workflow.add_default_row_task_creator = MagicMock(
            create_task=lambda table: _op(f"add-default-row-to-dw-{table.table_name}")
        )
        workflow.data_quality_tests_task_creator = MagicMock(
            create_task=lambda table: _op(f"data-quality-tests-dw-{table.table_name}")
        )
        workflow.register_delta_table_task_creator = MagicMock(
            create_task=lambda table: _op(f"register-{table.table_name}")
        )
        workflow.sync_metadata_task_creator = MagicMock(
            create_task=lambda table, *a, **k: _op(f"sync-{table.table_name}")
        )

    def _table(
        self, workflow: DwQueryDeltaWorkflow, table_name: str
    ) -> TableAttributes:
        return TableAttributes(
            workflow.dag_args, workflow.workflow_args, LayerEnum.DW, table_name
        )

    def test_default_keeps_dq_parallel_with_add_default_row(self):
        # arrange — flag omitted (default false)
        workflow = self._workflow()
        dag = DAG(
            dag_id="test_dw_query_delta_dq_default_parallel",
            schedule=None,
            start_date=datetime(2024, 1, 1),
        )
        self._bind_creators(workflow, dag)
        optimize = EmptyOperator(task_id="optimize-delta-tables", dag=dag)
        table = self._table(workflow, "dim_cost_center")

        with patch.object(
            workflow, "_check_include_data_quality_task", return_value=True
        ):
            load, last = workflow._create_dw_tasks(table, optimize)

        add_default = dag.get_task("add-default-row-to-dw-dim_cost_center")
        dq = dag.get_task("data-quality-tests-dw-dim_cost_center")

        assert add_default.task_id in load.downstream_task_ids
        assert dq.task_id in load.downstream_task_ids
        assert dq.task_id not in add_default.downstream_task_ids
        assert last.task_id == add_default.task_id

    def test_opt_in_serializes_dq_after_add_default_row(self):
        # arrange
        workflow = self._workflow(serialize_dq_after_default_row=True)
        dag = DAG(
            dag_id="test_dw_query_delta_dq_opt_in_serialize",
            schedule=None,
            start_date=datetime(2024, 1, 1),
        )
        self._bind_creators(workflow, dag)
        optimize = EmptyOperator(task_id="optimize-delta-tables", dag=dag)
        table = self._table(workflow, "dim_cost_center")

        with patch.object(
            workflow, "_check_include_data_quality_task", return_value=True
        ):
            load, last = workflow._create_dw_tasks(table, optimize)

        add_default = dag.get_task("add-default-row-to-dw-dim_cost_center")
        dq = dag.get_task("data-quality-tests-dw-dim_cost_center")

        assert add_default.task_id in load.downstream_task_ids
        assert dq.task_id in add_default.downstream_task_ids
        assert dq.task_id not in load.downstream_task_ids
        assert optimize.task_id in dq.downstream_task_ids
        assert last.task_id == add_default.task_id

    def test_opt_in_fact_without_default_row_still_depends_on_load(self):
        # arrange — flag on but facts have no add-default-row; last_task == load
        workflow = self._workflow(serialize_dq_after_default_row=True)
        dag = DAG(
            dag_id="test_dw_query_delta_dq_opt_in_fact",
            schedule=None,
            start_date=datetime(2024, 1, 1),
        )
        self._bind_creators(workflow, dag)
        optimize = EmptyOperator(task_id="optimize-delta-tables", dag=dag)
        table = self._table(workflow, "fact_employees")

        with patch.object(
            workflow, "_check_include_data_quality_task", return_value=True
        ):
            load, last = workflow._create_dw_tasks(table, optimize)

        assert "add-default-row-to-dw-fact_employees" not in {
            t.task_id for t in dag.tasks
        }
        dq = dag.get_task("data-quality-tests-dw-fact_employees")
        assert dq.task_id in load.downstream_task_ids
        assert last.task_id == load.task_id
