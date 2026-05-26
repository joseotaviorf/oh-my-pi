from unittest import mock

import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.enrich_query_delta_workflow import (
    EnrichQueryDeltaWorkflow,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestValidationWorkflow:
    def test_validation_workflow_flags(self):
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "consolidation_s_general_single_node_cluster"},
                dataset_dependencies=mock.MagicMock(),
                is_validation=True,
                validation_config={
                    "cluster": {"type": "consolidation_s_general_single_node_cluster"}
                },
            )

        assert workflow.is_validation is True
        assert workflow.dag_name == "pilot"
        assert workflow.dag_id == "bietlejuice.pilot__validation"
        assert workflow.dataset_dependencies == []

    def test_prod_workflow_keeps_dataset_dependencies(self):
        deps = mock.MagicMock()
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "databricks_16_4_med_general_cluster"},
                dataset_dependencies=deps,
            )

        assert workflow.is_validation is False
        assert workflow.dag_name == "pilot"
        assert workflow.dag_id == "bietlejuice.pilot"
        assert workflow.dataset_dependencies is deps

    def test_validation_list_queries_uses_prod_dag_name(self):
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "consolidation_s_general_single_node_cluster"},
                dataset_dependencies=mock.MagicMock(),
                is_validation=True,
                validation_config={
                    "cluster": {"type": "consolidation_s_general_single_node_cluster"}
                },
            )

        with mock.patch.object(
            DAGPackagesPathService,
            "list_queries_files_in_composer",
            return_value=["table_a"],
        ) as list_queries:
            tables = workflow._get_tables()

        list_queries.assert_called_once_with(
            dag_name="pilot", layer=workflow.layer.value
        )
        assert len(tables) == 1

    def test_base_workflow_dag_id_suffix_only_when_validation(self):
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            prod = BaseWorkflow(
                dag_args={"name": "my_dag", "owner": "o"},
                workflow_args={},
                cluster_args={},
            )
            validation = BaseWorkflow(
                dag_args={"name": "my_dag", "owner": "o"},
                workflow_args={},
                cluster_args={},
                is_validation=True,
            )

        assert prod.dag_id == "bietlejuice.my_dag"
        assert validation.dag_id == "bietlejuice.my_dag__validation"
        assert validation.dag_name == "my_dag"

    @pytest.fixture
    def _dag_instance_mocks(self):
        """Patch all Airflow/infrastructure calls needed to exercise dag_instance()."""
        with (
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DAG"
            ) as mock_dag,
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.JiraOpsCallback"
            ),
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DatabricksIncidentContextEnricher"
            ),
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.BaseDAG.get_default_trigger_form_params",
                return_value={},
            ),
            mock.patch.object(
                BaseWorkflow, "_get_start_date", return_value=mock.MagicMock()
            ),
            mock.patch.object(BaseWorkflow, "_get_dag_documentation", return_value=""),
        ):
            yield mock_dag

    def test_validation_dag_has_no_schedule(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={},
                cluster_args={},
                is_validation=True,
            )
        workflow.dag_instance()
        assert mock_dag_cls.call_args.kwargs["schedule"] is None

    def test_prod_dag_uses_schedule_interval(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            workflow = BaseWorkflow(
                dag_args={
                    "name": "pilot",
                    "owner": "Data Engineering",
                    "schedule_interval": "0 6 * * *",
                },
                workflow_args={},
                cluster_args={},
                is_validation=False,
            )
        workflow.dag_instance()
        assert mock_dag_cls.call_args.kwargs["schedule"] == "0 6 * * *"

    def test_validation_dag_has_cluster_validation_tag(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={},
                cluster_args={},
                is_validation=True,
            )
        workflow.dag_instance()
        tags = mock_dag_cls.call_args.kwargs["tags"]
        assert "cluster_validation" in tags

    def test_prod_dag_does_not_have_cluster_validation_tag(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": "prod"}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={},
                cluster_args={},
                is_validation=False,
            )
        workflow.dag_instance()
        tags = mock_dag_cls.call_args.kwargs["tags"]
        assert tags is None or "cluster_validation" not in (tags or [])
