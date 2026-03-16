"""
Unit tests for BaseWorkflow._data_quality_tables_cache.

Verifies that the instance-level dict cache in _get_data_quality_tables:
  - loads data on first call per layer
  - does not call the underlying service again on subsequent calls for the same layer
  - caches each layer independently
  - drives correct results through _check_include_data_quality_task
"""

from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.pipeline.layer_enum import LayerEnum


@pytest.fixture
def base_workflow():
    """
    Return a BaseWorkflow instance with all heavy __init__ dependencies mocked.

    ConfigurationService is patched at import level so the constructor does not
    attempt any filesystem or process-environment I/O.
    """
    with patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    ):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
            BaseWorkflow,
        )

        dag_args = {"name": "test_dag", "owner": "Data Platform"}
        workflow_args = {}
        cluster_args = {}

        # BaseWorkflow is abstract via BuilderInterface; create a minimal concrete
        # subclass so we can instantiate it without implementing build_dag / dag_instance.
        class ConcreteWorkflow(BaseWorkflow):
            def build_dag(self):
                pass

            def dag_instance(self, **kwargs):
                pass

        return ConcreteWorkflow(dag_args, workflow_args, cluster_args)


class TestBaseWorkflowDataQualityCache:
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    def test_get_data_quality_tables_populates_cache_on_first_call(
        self, mock_list_dq, base_workflow
    ):
        # arrange
        mock_list_dq.return_value = {"table_a", "table_b"}

        # act
        result = base_workflow._get_data_quality_tables("clean")

        # assert — cache entry created for the layer inside the shared DataQualityLayerCache
        assert "clean" in base_workflow._dq_cache._cache
        assert result == {"table_a", "table_b"}

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    def test_get_data_quality_tables_does_not_call_service_again_same_layer(
        self, mock_list_dq, base_workflow
    ):
        # arrange
        mock_list_dq.return_value = {"table_a"}

        # act — call twice with the same layer
        base_workflow._get_data_quality_tables("enrich")
        base_workflow._get_data_quality_tables("enrich")

        # assert — underlying service invoked exactly once
        mock_list_dq.assert_called_once_with("test_dag", "enrich")

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    def test_get_data_quality_tables_different_layers_cached_independently(
        self, mock_list_dq, base_workflow
    ):
        # arrange — service returns distinct sets per layer
        mock_list_dq.side_effect = lambda dag_name, layer: {
            "clean": {"clean_table"},
            "enrich": {"enrich_table"},
        }[layer]

        # act
        clean_tables = base_workflow._get_data_quality_tables("clean")
        enrich_tables = base_workflow._get_data_quality_tables("enrich")

        # assert — each layer has its own cache entry with the correct content
        assert clean_tables == {"clean_table"}
        assert enrich_tables == {"enrich_table"}
        assert mock_list_dq.call_count == 2

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    def test_check_include_data_quality_task_returns_true_for_known_table(
        self, mock_list_dq, base_workflow
    ):
        # arrange
        mock_list_dq.return_value = {"known_table"}
        table_attrs = MagicMock()
        table_attrs.table_name = "known_table"
        table_attrs.layer = LayerEnum.CLEAN

        # act
        result = base_workflow._check_include_data_quality_task(table_attrs)

        # assert
        assert result is True

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    def test_check_include_data_quality_task_returns_false_for_unknown_table(
        self, mock_list_dq, base_workflow
    ):
        # arrange
        mock_list_dq.return_value = {"other_table"}
        table_attrs = MagicMock()
        table_attrs.table_name = "missing_table"
        table_attrs.layer = LayerEnum.CLEAN

        # act
        result = base_workflow._check_include_data_quality_task(table_attrs)

        # assert
        assert result is False
