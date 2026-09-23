"""
Unit tests for the SLA deadline tag BaseWorkflow puts on every DAG it builds.

dag_runtime_monitoring only alerts on DAGs carrying an sla_deadline_localtime
tag, so a tiered DAG that declares no deadline must still get its tier default.
"""

from unittest.mock import patch

import pytest


@pytest.fixture
def workflow_factory():
    with patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    ):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
            BaseWorkflow,
        )

        class ConcreteWorkflow(BaseWorkflow):
            def build_dag(self):
                pass

            def _get_dag_documentation(self):
                return ""

        def build(**dag_args):
            base = {
                "name": "test_dag",
                "owner": "Data Platform",
                "schedule_interval": "0 1 * * *",
            }
            return ConcreteWorkflow({**base, **dag_args}, {}, {}).dag_instance()

        yield build


class TestBaseWorkflowSlaDeadlineTag:
    @pytest.mark.parametrize("tier", ["Critical", "High"])
    def test_paging_tier_without_declared_deadline_gets_eight_oclock(
        self, workflow_factory, tier
    ):
        assert "sla_deadline_localtime:08:00" in workflow_factory(criticality=tier).tags

    @pytest.mark.parametrize("tier", ["Medium", "Low"])
    def test_lower_tier_without_declared_deadline_gets_eleven_oclock(
        self, workflow_factory, tier
    ):
        assert "sla_deadline_localtime:11:00" in workflow_factory(criticality=tier).tags

    def test_declared_deadline_overrides_the_tier_default(self, workflow_factory):
        tags = workflow_factory(criticality="High", sla_deadline_localtime="11:00").tags
        assert "sla_deadline_localtime:11:00" in tags
        assert "sla_deadline_localtime:08:00" not in tags

    def test_dag_without_criticality_gets_no_deadline_tag(self, workflow_factory):
        tags = workflow_factory().tags
        assert not [tag for tag in tags if tag.startswith("sla_deadline_localtime:")]
