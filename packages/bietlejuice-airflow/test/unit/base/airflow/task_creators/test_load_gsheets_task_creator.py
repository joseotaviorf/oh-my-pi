"""Unit tests for LoadGsheetsTaskCreator Spark job argument contract."""

from unittest import mock
from unittest.mock import MagicMock

import pytest

from bietlejuice.base.airflow.task_creators.load_gsheets_task_creator import (
    LoadGsheetsTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestLoadGsheetsTaskCreator:
    """Trava a ordem/contagem dos args posicionais de load_gsheets_full_overwrite."""

    def _ctx(self, workflow_args):
        ctx = MagicMock()
        ctx.environment = "forno"
        ctx.bucket = "test-bucket"
        ctx.workflow_args = workflow_args
        ctx.is_validation = False
        return ctx

    def _attrs(self, workflow_args):
        return TableAttributes(
            dag_args={"name": "gsheets_luigijr_my_sheet"},
            workflow_args=workflow_args,
            layer=LayerEnum.CLEAN,
            table_name="my_sheet",
        )

    def test_parameters_order_defaults(self):
        workflow_args = {
            "custom_schema": "gsheets",
            "tables_customization": {
                "my_sheet": {"sheet_id": "abc123", "sheet_name": "Sheet1"}
            },
        }
        creator = LoadGsheetsTaskCreator(self._ctx(workflow_args))
        params = creator._get_parameters(self._attrs(workflow_args))

        assert params == [
            "forno",  # environment
            "test-bucket",  # bucket
            "gsheets",  # source (custom_schema)
            "my_sheet",  # table_name
            "abc123",  # sheet_id
            "Sheet1",  # sheet_name
            "GOOGLE_SERVICE_ACCOUNT_CREDENTIALS",  # credentials_key (default)
            "quintoandar",  # credentials_scope (default)
        ]

    def test_credentials_overridable_via_workflow_args(self):
        workflow_args = {
            "custom_schema": "gsheets",
            "gsheets_credentials_key": "MY_SA_KEY",
            "gsheets_credentials_scope": "my_scope",
            "tables_customization": {
                "my_sheet": {"sheet_id": "abc123", "sheet_name": "Sheet1"}
            },
        }
        creator = LoadGsheetsTaskCreator(self._ctx(workflow_args))
        params = creator._get_parameters(self._attrs(workflow_args))

        assert params[6] == "MY_SA_KEY"
        assert params[7] == "my_scope"

    def test_missing_sheet_id_raises(self):
        workflow_args = {
            "custom_schema": "gsheets",
            "tables_customization": {"my_sheet": {"sheet_name": "Sheet1"}},
        }
        creator = LoadGsheetsTaskCreator(self._ctx(workflow_args))
        with pytest.raises(KeyError):
            creator._get_parameters(self._attrs(workflow_args))

    def test_validation_appends_target_args(self):
        """Regression: is_validation=True must redirect writes to isolated validation target."""
        workflow_args = {
            "custom_schema": "gsheets",
            "tables_customization": {
                "my_sheet": {"sheet_id": "abc123", "sheet_name": "Sheet1"}
            },
        }
        ctx = self._ctx(workflow_args)
        ctx.is_validation = True
        creator = LoadGsheetsTaskCreator(ctx)
        attrs = self._attrs(workflow_args)

        with mock.patch.object(
            attrs,
            "get_validation_write_target",
            return_value=("cluster_validation", "datalake_gsheets_clean___my_sheet"),
        ):
            params = creator._get_parameters(attrs)

        # Positional args unchanged
        assert params[:8] == [
            "forno",
            "test-bucket",
            "gsheets",
            "my_sheet",
            "abc123",
            "Sheet1",
            "GOOGLE_SERVICE_ACCOUNT_CREDENTIALS",
            "quintoandar",
        ]
        # Validation target flags appended
        assert "--target-database-name" in params
        assert "--target-table-name" in params
        tdn_idx = params.index("--target-database-name")
        assert params[tdn_idx + 1] == "cluster_validation"
        ttn_idx = params.index("--target-table-name")
        assert params[ttn_idx + 1] == "datalake_gsheets_clean___my_sheet"

    def test_no_validation_flags_when_not_validation(self):
        """Non-validation run must NOT append --target-* flags."""
        workflow_args = {
            "custom_schema": "gsheets",
            "tables_customization": {
                "my_sheet": {"sheet_id": "abc123", "sheet_name": "Sheet1"}
            },
        }
        creator = LoadGsheetsTaskCreator(self._ctx(workflow_args))
        params = creator._get_parameters(self._attrs(workflow_args))

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params
