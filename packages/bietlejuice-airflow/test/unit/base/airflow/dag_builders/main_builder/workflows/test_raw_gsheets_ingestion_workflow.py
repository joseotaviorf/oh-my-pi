"""Unit tests for RawGsheetsIngestionWorkflow (single-step gsheets overwrite).

Lazy import of the workflow (mesmo motivo do test_raw_api_ingestion_workflow): evita carregar
BaseWorkflow/TaskCreatorFactory/DatasetService na coleta.
"""

from unittest.mock import Mock, patch

import pytest

from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestRawGsheetsIngestionWorkflow:
    @pytest.fixture(scope="class")
    def workflow_class(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_ingestion_workflow import (
            RawGsheetsIngestionWorkflow,
        )

        return RawGsheetsIngestionWorkflow

    @pytest.fixture(scope="class")
    def base_workflow_module(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows import (
            base_workflow,
        )

        return base_workflow

    class _DummyTask:
        """Task stub que suporta o `>>` do Airflow."""

        def __init__(self, task_id):
            self.task_id = task_id

        def __rshift__(self, other):
            return other

    @pytest.fixture
    def mock_config_service(self):
        cs = Mock()
        cs.get_config = Mock(return_value="test-bucket")
        return cs

    @pytest.fixture
    def patch_configuration_service(self, mock_config_service):
        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
        ) as mock_cls:
            mock_cls.return_value = mock_config_service
            yield mock_cls

    def _build(
        self,
        workflow_class,
        base_workflow_module,
        dag_args,
        workflow_args,
        is_validation=False,
    ):
        cluster_args = {
            "type": "consolidation_xs_general_cluster",
            "databricks_conn_id": "databricks_new",
        }
        wf = workflow_class(
            dag_args, workflow_args, cluster_args, is_validation=is_validation
        )

        creators = {k: Mock() for k in ("exec", "load", "sync", "dummy")}
        for name, tc in creators.items():
            tc.create_task.return_value = self._DummyTask(name)

        def _init(_ctx):
            wf.execute_job_cluster_task_creator = creators["exec"]
            wf.load_gsheets_task_creator = creators["load"]
            wf.sync_metadata_task_creator = creators["sync"]
            wf.dummy_job_cluster_finished_task_creator = creators["dummy"]

        with (
            patch.object(
                base_workflow_module.BaseWorkflow, "dag_instance", return_value=Mock()
            ),
            patch.object(
                workflow_class, "_get_dag_execution_context", return_value=Mock()
            ),
            patch.object(
                workflow_class, "_initialize_task_creators", side_effect=_init
            ),
        ):
            wf.build_dag()
        return creators

    def test_build_dag_wires_load_then_sync_trino(
        self, workflow_class, base_workflow_module, patch_configuration_service
    ):
        creators = self._build(
            workflow_class,
            base_workflow_module,
            {
                "name": "gsheets_luigijr_vendas",
                "owner": "Data Fintech",
                "schedule_interval": "0 8 * * *",
            },
            {
                "type": "gsheets_ingestion",
                "layer": "raw",
                "custom_schema": "gsheets",
                "tables_customization": {
                    "vendas": {"sheet_id": "abc", "sheet_name": "Sheet1"}
                },
            },
        )

        creators["load"].create_task.assert_called_once()
        creators["sync"].create_task.assert_called_once()

        # sync roda só o hive sync (Trino), sem lineage
        assert (
            creators["sync"].create_task.call_args.kwargs.get("bypass_task")
            == "--bypass-propagate"
        )
        # sync localiza a tabela no schema CLEAN (datalake_<schema>_clean)
        sync_attrs = creators["sync"].create_task.call_args.args[0]
        assert sync_attrs.layer == LayerEnum.CLEAN

    def test_build_dag_uma_task_de_cada_por_planilha(
        self, workflow_class, base_workflow_module, patch_configuration_service
    ):
        creators = self._build(
            workflow_class,
            base_workflow_module,
            {
                "name": "gsheets_luigijr_multi",
                "owner": "Data Fintech",
                "schedule_interval": "0 8 * * *",
            },
            {
                "type": "gsheets_ingestion",
                "layer": "raw",
                "custom_schema": "gsheets",
                "tables_customization": {
                    "t1": {"sheet_id": "a", "sheet_name": "S1"},
                    "t2": {"sheet_id": "b", "sheet_name": "S2"},
                },
            },
        )
        assert creators["load"].create_task.call_count == 2
        assert creators["sync"].create_task.call_count == 2

    def test_build_dag_skips_sync_on_validation_dag(
        self, workflow_class, base_workflow_module, patch_configuration_service
    ):
        # Regressão: em DAGs de validação (is_validation) o hive sync deve ser pulado,
        # assim como nos demais workflows (BaseWorkflow._check_include_sync_hive_tasks).
        creators = self._build(
            workflow_class,
            base_workflow_module,
            {
                "name": "gsheets_luigijr_vendas",
                "owner": "Data Fintech",
                "schedule_interval": "0 8 * * *",
            },
            {
                "type": "gsheets_ingestion",
                "layer": "raw",
                "custom_schema": "gsheets",
                "tables_customization": {
                    "vendas": {"sheet_id": "abc", "sheet_name": "Sheet1"}
                },
            },
            is_validation=True,
        )

        creators["load"].create_task.assert_called_once()
        creators["sync"].create_task.assert_not_called()

    def test_build_dag_respects_has_hive_sync_false(
        self, workflow_class, base_workflow_module, patch_configuration_service
    ):
        # Regressão: has_hive_sync=false no nível de workflow deve desabilitar o sync.
        creators = self._build(
            workflow_class,
            base_workflow_module,
            {
                "name": "gsheets_luigijr_vendas",
                "owner": "Data Fintech",
                "schedule_interval": "0 8 * * *",
            },
            {
                "type": "gsheets_ingestion",
                "layer": "raw",
                "custom_schema": "gsheets",
                "has_hive_sync": False,
                "tables_customization": {
                    "vendas": {"sheet_id": "abc", "sheet_name": "Sheet1"}
                },
            },
        )

        creators["load"].create_task.assert_called_once()
        creators["sync"].create_task.assert_not_called()

    def test_build_dag_respects_table_level_has_hive_sync_false(
        self, workflow_class, base_workflow_module, patch_configuration_service
    ):
        # Regressão: has_hive_sync=false no nível da tabela (table_customization)
        # deve desabilitar o sync mesmo com o default do workflow habilitado.
        creators = self._build(
            workflow_class,
            base_workflow_module,
            {
                "name": "gsheets_luigijr_vendas",
                "owner": "Data Fintech",
                "schedule_interval": "0 8 * * *",
            },
            {
                "type": "gsheets_ingestion",
                "layer": "raw",
                "custom_schema": "gsheets",
                "tables_customization": {
                    "vendas": {
                        "sheet_id": "abc",
                        "sheet_name": "Sheet1",
                        "has_hive_sync": False,
                    }
                },
            },
        )

        creators["load"].create_task.assert_called_once()
        creators["sync"].create_task.assert_not_called()
