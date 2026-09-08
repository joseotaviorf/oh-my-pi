"""Unit tests for BaseQueryDeltaWorkflow._max_tables_per_cluster configuration."""

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.clean_query_delta_workflow import (
    CleanQueryDeltaWorkflow,
)


class TestBaseQueryDeltaWorkflowMaxTablesPerCluster:
    def _workflow(self, **workflow_overrides) -> CleanQueryDeltaWorkflow:
        workflow_args = {
            "type": "query_delta",
            "layer": "clean",
            "custom_schema": "amplitude",
            "default_extraction_type": "incremental",
            **workflow_overrides,
        }
        return CleanQueryDeltaWorkflow(
            {"name": "amplitude_subpartitioned", "owner": "Data Growth"},
            workflow_args,
            {"type": "consolidation_m_general_cluster"},
        )

    def test_max_tables_per_cluster_defaults_to_class_constant(self):
        workflow = self._workflow()

        assert (
            workflow._max_tables_per_cluster()
            == CleanQueryDeltaWorkflow.MAX_TABLES_PER_CLUSTER
        )

    def test_max_tables_per_cluster_reads_workflow_override(self):
        workflow = self._workflow(max_tables_per_cluster=400)

        assert workflow._max_tables_per_cluster() == 400
