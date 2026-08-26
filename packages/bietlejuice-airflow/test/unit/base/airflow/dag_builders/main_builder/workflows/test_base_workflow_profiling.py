"""Unit tests for BaseWorkflow._check_include_profiling_task."""

from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.observability.profiling_config import ProfilingConfig


@pytest.fixture
def base_workflow():
    with patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    ):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
            BaseWorkflow,
        )

        class ConcreteWorkflow(BaseWorkflow):
            def build_dag(self):
                pass

            def dag_instance(self, **kwargs):
                pass

        return ConcreteWorkflow(
            {"name": "test_dag", "owner": "Data Platform"},
            {},
            {},
        )


def _table(name: str) -> MagicMock:
    table_attrs = MagicMock()
    table_attrs.table_name = name
    return table_attrs


class TestCheckIncludeProfilingTask:
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ProfilingConfig.from_configuration_service"
    )
    def test_enabled_without_allowlist_profiles_all_tables(
        self, mock_from_cs, base_workflow
    ):
        # arrange
        mock_from_cs.return_value = ProfilingConfig(
            kill_switch=True, default_enabled=False
        )
        base_workflow.workflow_args["observability"] = {"enabled": True}

        # act / assert
        assert base_workflow._check_include_profiling_task(_table("traces")) is True
        assert base_workflow._check_include_profiling_task(_table("other")) is True

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ProfilingConfig.from_configuration_service"
    )
    def test_allowlist_profiles_only_listed_tables(self, mock_from_cs, base_workflow):
        # arrange
        mock_from_cs.return_value = ProfilingConfig(
            kill_switch=True, default_enabled=False
        )
        base_workflow.workflow_args["observability"] = {
            "enabled": True,
            "tables": ["traces", "sessions"],
        }

        # act / assert
        assert base_workflow._check_include_profiling_task(_table("traces")) is True
        assert base_workflow._check_include_profiling_task(_table("sessions")) is True
        assert base_workflow._check_include_profiling_task(_table("other")) is False

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ProfilingConfig.from_configuration_service"
    )
    def test_disabled_dag_never_profiles_even_with_allowlist(
        self, mock_from_cs, base_workflow
    ):
        # arrange
        mock_from_cs.return_value = ProfilingConfig(
            kill_switch=True, default_enabled=False
        )
        base_workflow.workflow_args["observability"] = {
            "enabled": False,
            "tables": ["traces"],
        }

        # act / assert
        assert base_workflow._check_include_profiling_task(_table("traces")) is False

    def test_validation_dag_never_profiles(self, base_workflow):
        # arrange
        base_workflow.is_validation = True
        base_workflow.workflow_args["observability"] = {"enabled": True}

        # act / assert
        assert base_workflow._check_include_profiling_task(_table("traces")) is False
