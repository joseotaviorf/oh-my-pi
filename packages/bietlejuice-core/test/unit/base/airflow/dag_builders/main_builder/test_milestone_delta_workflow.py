"""Unit tests for milestone_delta declaration validation."""

from __future__ import annotations

import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


def _base_declaration(tables_customization: dict) -> dict:
    return {
        "dag": {
            "name": "dw_example_milestones",
            "owner": "Data Agents",
            "schedule_start_date": "2026, 1, 1",
            "schedule_interval": "0 6 * * *",
        },
        "workflow": {
            "type": WorkflowEnum.MILESTONE_DELTA_WORKFLOW.value,
            "layer": "dw",
            "custom_schema": "example",
            "tables_customization": tables_customization,
        },
        "cluster": {"type": "emr_7_12_consolidation_xs_general_single_node_cluster"},
        "validation": {"allow_custom_spark_job": True},
    }


def test_milestone_delta_defaults_job_and_prefix():
    decl = _base_declaration(
        {
            "dim_example": {
                "extraction_type": "full",
                "merge_on": ["sk_user", "milestone_type"],
            }
        }
    )
    # Call only the milestone validator (full validate needs more cluster context)
    DAGDeclarationValidator()._validate_milestone_delta_workflow(decl)
    workflow = decl["workflow"]
    assert workflow["load_spark_job"] == "load_milestone_dimension"
    assert workflow["spark_job_prefix"] == "base"
    assert "--merge-on" in workflow["spark_job_arguments"]
    assert "{merge_on}" in workflow["spark_job_arguments"]


def test_milestone_delta_requires_entity_key():
    decl = _base_declaration(
        {
            "dim_example": {
                "extraction_type": "full",
                "merge_on": ["milestone_type"],
            }
        }
    )
    with pytest.raises(AssertionError, match="entity key"):
        DAGDeclarationValidator()._validate_milestone_delta_workflow(decl)


def test_workflow_enum_includes_milestone_delta():
    assert "milestone_delta" in WorkflowEnum.get_available_enum_values()
