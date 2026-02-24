"""
Unit tests for WorkflowEnum.

Tests the workflow enum, particularly focusing on API_INGESTION_WORKFLOW.
"""

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class TestWorkflowEnum:
    """Test suite for WorkflowEnum class."""

    def test_api_ingestion_workflow_exists(self):
        """Test that API_INGESTION_WORKFLOW enum member exists."""
        assert hasattr(WorkflowEnum, "API_INGESTION_WORKFLOW")
        assert WorkflowEnum.API_INGESTION_WORKFLOW.value == "api_ingestion"

    def test_get_available_enum_values_includes_api_ingestion(self):
        """Test that get_available_enum_values includes api_ingestion."""
        values = WorkflowEnum.get_available_enum_values()
        assert "api_ingestion" in values

    def test_all_workflow_enums_have_values(self):
        """Test that all workflow enum members have string values."""
        for member in WorkflowEnum:
            assert isinstance(member.value, str)
            assert len(member.value) > 0

    def test_api_ingestion_workflow_can_be_accessed_by_value(self):
        """Test that API_INGESTION_WORKFLOW can be accessed by value."""
        workflow = WorkflowEnum("api_ingestion")
        assert workflow == WorkflowEnum.API_INGESTION_WORKFLOW
