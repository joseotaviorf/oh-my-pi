"""Unit tests for LoadCDCCleanTaskCreator Spark job arguments (EMR-safe optional flags)."""

from unittest.mock import MagicMock

import pytest

from bietlejuice.base.airflow.task_creators.load_cdc_clean_task_creator import (
    LoadCDCCleanTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_delta_table_task_creator import (
    LoadDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestLoadCDCCleanTaskCreatorRowFilterArgs:
    @pytest.fixture
    def config_service(self):
        svc = MagicMock()
        svc.get_config.return_value = "data-documentation-bucket"
        return svc

    @pytest.fixture
    def dag_execution_context(self):
        ctx = MagicMock()
        ctx.dag_args = {"name": "datazord"}
        ctx.environment = "forno"
        ctx.bucket = "5a-datalake-forno"
        ctx.load_start_date = "2026-04-01"
        ctx.load_end_date = "2026-04-02"
        return ctx

    def _base_workflow_args(self):
        return {
            "custom_schema": "datazord",
            "tables_customization": {
                "business_object": {
                    "clean_primary_keys": ["sk_business_object"],
                }
            },
        }

    def test_get_parameters_omits_row_filter_flags_when_not_configured(
        self, dag_execution_context, config_service
    ):
        table_attributes = TableAttributes(
            dag_args=dag_execution_context.dag_args,
            workflow_args=self._base_workflow_args(),
            layer=LayerEnum.CLEAN,
            table_name="business_object",
        )
        creator = LoadCDCCleanTaskCreator(dag_execution_context, config_service)
        params = creator._get_parameters(table_attributes)

        assert "--row-filter-column-key" not in params
        assert "--row-filter-function-name" not in params

    def test_get_parameters_includes_row_filter_flags_when_configured(
        self, dag_execution_context, config_service
    ):
        workflow = self._base_workflow_args()
        workflow["tables_customization"]["business_object"].update(
            {
                "row_filter_column_key": "uuid_person",
                "row_filter": "has_3p_access",
            }
        )
        table_attributes = TableAttributes(
            dag_args=dag_execution_context.dag_args,
            workflow_args=workflow,
            layer=LayerEnum.CLEAN,
            table_name="business_object",
        )
        creator = LoadCDCCleanTaskCreator(dag_execution_context, config_service)
        params = creator._get_parameters(table_attributes)

        rfck_i = params.index("--row-filter-column-key")
        assert params[rfck_i + 1] == "uuid_person"
        rffn_i = params.index("--row-filter-function-name")
        assert (
            params[rffn_i + 1]
            == "data_governance_policies.has_3p_access_control_row_filter"
        )


class TestLoadDeltaTableTaskCreatorRowFilterArgs:
    @pytest.fixture
    def dag_execution_context(self):
        ctx = MagicMock()
        ctx.environment = "forno"
        ctx.bucket = "test-bucket"
        ctx.dag_args = {"name": "dw_test"}
        ctx.execution_date = "2025-01-15"
        ctx.load_start_date = "2025-01-01"
        ctx.load_end_date = "2025-01-16"
        ctx.workflow_args = {"default_partitions": []}
        return ctx

    def test_get_parameters_omits_row_filter_flags_when_not_configured(
        self, dag_execution_context
    ):
        table_attributes = TableAttributes(
            dag_args=dag_execution_context.dag_args,
            workflow_args={
                "custom_schema": "public",
                "tables_customization": {
                    "my_table": {},
                },
            },
            layer=LayerEnum.DW,
            table_name="my_table",
        )
        creator = LoadDeltaTableTaskCreator(dag_execution_context)
        params = creator._get_parameters(table_attributes)

        assert "--row-filter-column-key" not in params
        assert "--row-filter-function-name" not in params
        assert "--table-privileges" in params
