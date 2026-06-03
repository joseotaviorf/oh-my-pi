import json
from unittest import mock

import pytest

from bietlejuice.base.airflow.task_creators.create_query_view_task_creator import (
    CreateQueryViewTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestCreateQueryViewTaskCreator:
    @pytest.fixture
    def dag_execution_context(self):
        context = mock.MagicMock()
        context.environment = "forno"
        context.bucket = "test_bucket"
        context.dag_args = {"name": "enrich_test_view"}
        context.workflow_args = {
            "layer": "enrich",
            "sync": ["databricks", "trino"],
            "sql_dialect": "databricks",
        }
        context.execution_date = "{{ data_interval_start | ds }}"
        context.load_start_date = "{{ load_start_date }}"
        context.load_end_date = "{{ load_end_date }}"
        return context

    def test_get_parameters_uses_workflow_sync_config(self, dag_execution_context):
        # arrange
        creator = CreateQueryViewTaskCreator(dag_execution_context)
        table_attributes = TableAttributes(
            dag_args=dag_execution_context.dag_args,
            workflow_args=dag_execution_context.workflow_args,
            layer=LayerEnum.ENRICH,
            table_name="test_view",
        )

        # act
        parameters = creator._get_parameters(table_attributes)

        # assert
        assert json.loads(_get_flag_value(parameters, "--sync")) == [
            "databricks",
            "trino",
        ]
        assert _get_flag_value(parameters, "--sql-dialect") == "databricks"
        assert "--has-hive-sync" not in parameters

    def test_get_parameters_uses_table_sync_override(self, dag_execution_context):
        # arrange
        dag_execution_context.workflow_args["tables_customization"] = {
            "test_view": {"sync": ["trino"], "sql_dialect": "trino"}
        }
        creator = CreateQueryViewTaskCreator(dag_execution_context)
        table_attributes = TableAttributes(
            dag_args=dag_execution_context.dag_args,
            workflow_args=dag_execution_context.workflow_args,
            layer=LayerEnum.ENRICH,
            table_name="test_view",
        )

        # act
        parameters = creator._get_parameters(table_attributes)

        # assert
        assert json.loads(_get_flag_value(parameters, "--sync")) == ["trino"]
        assert _get_flag_value(parameters, "--sql-dialect") == "trino"


def _get_flag_value(parameters: list[str], flag: str) -> str:
    return parameters[parameters.index(flag) + 1]
