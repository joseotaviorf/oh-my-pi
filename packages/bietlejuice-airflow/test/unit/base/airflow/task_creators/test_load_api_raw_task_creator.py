"""Unit tests for LoadAPIRawTaskCreator Spark job argument contract."""

from unittest.mock import MagicMock

import pytest

from bietlejuice.base.airflow.task_creators.load_api_raw_task_creator import (
    LoadAPIRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestLoadAPIRawTaskCreator:
    """Locks the positional argument order and count for load_api_ingestion_raw."""

    @pytest.fixture
    def dag_execution_context(self):
        ctx = MagicMock()
        ctx.environment = "forno"
        ctx.bucket = "test-bucket"
        ctx.dag_args = {"name": "dag_api_raw"}
        ctx.execution_date = "2025-01-15"
        ctx.load_start_date = "2025-01-01"
        ctx.load_end_date = "2025-01-16"
        ctx.workflow_args = {"spark_job_prefix": "base"}
        ctx.is_validation = False
        return ctx

    @pytest.fixture
    def table_attributes(self):
        return TableAttributes(
            dag_args={"name": "dag_api_raw"},
            workflow_args={
                "default_raw_partitions": ["year", "month", "day"],
            },
            layer=LayerEnum.RAW,
            table_name="my_table",
        )

    def test_get_parameters_order_and_count_matches_load_api_ingestion_raw(
        self, dag_execution_context, table_attributes
    ):
        creator = LoadAPIRawTaskCreator(dag_execution_context)
        params = creator._get_parameters(table_attributes)

        assert len(params) == 9
        assert params[0] == "forno"
        assert params[1] == "test-bucket"
        assert params[2] == "dag_api_raw"
        assert params[3] == "my_table"
        assert params[4] == "2025-01-15"
        assert params[5] == '["year", "month", "day"]'
        assert params[6] == "full"
        assert params[7] == "2025-01-01"
        assert params[8] == "2025-01-16"

    def test_get_parameters_uses_workflow_extra_when_table_has_none(
        self, dag_execution_context, table_attributes
    ):
        dag_execution_context.workflow_args["extra_query_template_params"] = {
            "load_start_date": "wf-start",
            "load_end_date": "wf-end",
        }

        creator = LoadAPIRawTaskCreator(dag_execution_context)
        params = creator._get_parameters(table_attributes)

        assert params[7] == "wf-start"
        assert params[8] == "wf-end"

    def test_get_parameters_table_extra_overrides_load_end_date_only(
        self, dag_execution_context
    ):
        dag_execution_context.workflow_args["extra_query_template_params"] = {
            "load_start_date": "wf-start",
            "load_end_date": "wf-end",
        }
        table_attributes = TableAttributes(
            dag_args={"name": "dag_api_raw"},
            workflow_args={"default_raw_partitions": ["year", "month", "day"]},
            layer=LayerEnum.RAW,
            table_name="my_table",
            table_customization={
                "extra_query_template_params": {
                    "load_end_date": (
                        "{{ get_date_param(dag_run, "
                        "macros.ds_add(data_interval_start | ds, 1), "
                        "'load_end_date') }}"
                    )
                }
            },
        )

        creator = LoadAPIRawTaskCreator(dag_execution_context)
        params = creator._get_parameters(table_attributes)

        assert params[7] == "2025-01-01"
        assert params[8] == (
            "{{ get_date_param(dag_run, "
            "macros.ds_add(data_interval_start | ds, 1), "
            "'load_end_date') }}"
        )

    def test_get_parameters_table_extra_overrides_both_dates(
        self, dag_execution_context
    ):
        dag_execution_context.workflow_args["extra_query_template_params"] = {
            "load_start_date": "wf-start",
            "load_end_date": "wf-end",
        }
        table_attributes = TableAttributes(
            dag_args={"name": "dag_api_raw"},
            workflow_args={"default_raw_partitions": ["year", "month", "day"]},
            layer=LayerEnum.RAW,
            table_name="my_table",
            table_customization={
                "extra_query_template_params": {
                    "load_start_date": "table-start",
                    "load_end_date": "table-end",
                }
            },
        )

        creator = LoadAPIRawTaskCreator(dag_execution_context)
        params = creator._get_parameters(table_attributes)

        assert params[7] == "table-start"
        assert params[8] == "table-end"

    def test_get_parameters_does_not_mutate_table_extra_dict(
        self, dag_execution_context
    ):
        table_extra = {"load_end_date": "table-end"}
        table_attributes = TableAttributes(
            dag_args={"name": "dag_api_raw"},
            workflow_args={"default_raw_partitions": ["year", "month", "day"]},
            layer=LayerEnum.RAW,
            table_name="my_table",
            table_customization={"extra_query_template_params": table_extra},
        )

        creator = LoadAPIRawTaskCreator(dag_execution_context)
        creator._get_parameters(table_attributes)

        assert table_extra == {"load_end_date": "table-end"}

    def test_get_parameters_does_not_mutate_workflow_extra_dict(
        self, dag_execution_context, table_attributes
    ):
        workflow_extra = {"load_start_date": "wf-start"}
        dag_execution_context.workflow_args["extra_query_template_params"] = (
            workflow_extra
        )

        creator = LoadAPIRawTaskCreator(dag_execution_context)
        params = creator._get_parameters(table_attributes)

        assert workflow_extra == {"load_start_date": "wf-start"}
        assert params[7] == "wf-start"
        assert params[8] == "2025-01-16"
