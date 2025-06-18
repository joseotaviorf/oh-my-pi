from unittest import mock
import pytest
import pendulum
from airflow.datasets import Dataset


class MockBaseTaskCreator:
    def __init__(self, dag_execution_context):
        self.dag_execution_context = dag_execution_context


class TestReprocessingGuardTaskCreator:
    @pytest.fixture(autouse=True)
    def mock_get_current_context(self):
        mock_base_task_creator_module = mock.MagicMock()
        mock_base_task_creator_module.BaseTaskCreator = MockBaseTaskCreator
        with mock.patch(
            "airflow.operators.python.get_current_context"
        ) as mock_get_current_context, mock.patch.dict(
            # So we don't have to install the databricks_plugin package
            "sys.modules",
            {
                "bietlejuice.base.airflow.task_creators.base_task_creator": mock_base_task_creator_module
            },
        ):
            task_instance = mock.MagicMock()
            task_instance.xcom_pull.return_value = None
            task = mock.MagicMock()
            task_instance.task = task
            task.task_id = "task"
            dag = mock.MagicMock()
            dag.dag_id = "current_dag"
            mock_get_current_context.return_value = {
                "params": {"run_type": "impact_downstream_dependents"},
                "triggering_dataset_events": {},
                "execution_date": pendulum.datetime(2025, 1, 1),
                "ti": task_instance,
                "task": task,
                "dag": dag,
            }
            yield mock_get_current_context

    @pytest.fixture
    def reprocessing_guard_task_creator(self):
        from bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator import (
            ReprocessingGuardTaskCreator,
        )

        dag_execution_context = mock.MagicMock()
        return ReprocessingGuardTaskCreator(dag_execution_context)

    def test_should_run_dag_if_not_a_reprocessing_run(
        self, reprocessing_guard_task_creator, mock_get_current_context
    ):
        mock_context = mock_get_current_context.return_value
        mock_context["params"]["run_type"] = "impact_downstream_dependents"

        assert reprocessing_guard_task_creator._should_run_dag() is True

    def test_should_run_dag_if_reprocessing_run_started_in_current_dag(
        self, reprocessing_guard_task_creator, mock_get_current_context
    ):
        mock_context = mock_get_current_context.return_value
        mock_context["params"]["run_type"] = "reprocessing_run"
        # No dataset triggered this run. It was triggered manually.
        mock_context["triggering_dataset_events"] = {}

        assert reprocessing_guard_task_creator._should_run_dag() is True

    def test_should_run_dag_if_reprocessing_run_if_all_dependencies_from_origin_have_finished(
        self, reprocessing_guard_task_creator, mock_get_current_context
    ):
        mock_context = mock_get_current_context.return_value
        mock_context["params"]["run_type"] = "reprocessing_run"
        mock_dataset_event = mock.MagicMock()
        mock_dataset_event.extra = {"reprocessing_source": "origin_dag"}
        mock_context["triggering_dataset_events"] = {
            "dep_1_dag:task:reprocessing": [mock_dataset_event]
        }

        with mock.patch(
            "bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator.BietlejuiceDependencyHelper.read_dependencies",
            return_value={
                "current_dag": ["dep_1_dag:task"],
                "dep_1_dag": ["origin_dag:task"],
            },
        ):
            assert reprocessing_guard_task_creator._should_run_dag() is True

    def test_should_not_run_dag_if_reprocessing_run_if_all_dependencies_from_origin_have_finished(
        self, reprocessing_guard_task_creator, mock_get_current_context
    ):
        mock_context = mock_get_current_context.return_value
        mock_context["params"]["run_type"] = "reprocessing_run"
        mock_dataset_event = mock.MagicMock()
        mock_dataset_event.extra = {"reprocessing_source": "origin_dag"}
        mock_context["triggering_dataset_events"] = {
            "dep_1_dag:task:reprocessing": [mock_dataset_event]
        }
        mock_context["dag"].timetable.dataset_condition = (
            Dataset("dep_1_dag:task") & Dataset("dep_2_dag:task")
        ) | (
            Dataset("dep_1_dag:task:reprocessing")
            & Dataset("dep_2_dag:task:reprocessing")
        )

        with mock.patch(
            "bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator.BietlejuiceDependencyHelper.read_dependencies",
            return_value={
                # Only dep_1_dag has finished, but dep_2_dag has not.
                "current_dag": ["dep_1_dag:task", "dep_2_dag:task"],
                "dep_2_dag": ["origin_dag:task"],
                "dep_1_dag": ["origin_dag:task"],
            },
        ):
            assert reprocessing_guard_task_creator._should_run_dag() is False
            # Must save the dependencies that have finished in XCOMs
            mock_context["ti"].xcom_push.assert_called_once_with(
                key="reprocessing_guard_origin_dag_dependencies",
                value=["dep_1_dag:task:reprocessing"],
            )

    def test_should_retrive_info_from_past_runs_from_xcom(
        self, reprocessing_guard_task_creator, mock_get_current_context
    ):
        mock_context = mock_get_current_context.return_value
        mock_context["params"]["run_type"] = "reprocessing_run"
        mock_dataset_event = mock.MagicMock()
        mock_dataset_event.extra = {"reprocessing_source": "origin_dag"}
        mock_context["triggering_dataset_events"] = {
            "dep_1_dag:task:reprocessing": [mock_dataset_event]
        }
        mock_context["dag"].timetable.dataset_condition = (
            Dataset("dep_1_dag:task") & Dataset("dep_2_dag:task")
        ) | (
            Dataset("dep_1_dag:task:reprocessing")
            | Dataset("dep_2_dag:task:reprocessing")
        )
        # Mocking the XCOM pull to simulate that dep_2_dag has finished in a previous run
        mock_context["ti"].xcom_pull.return_value = ["dep_2_dag:task:reprocessing"]

        with mock.patch(
            "bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator.BietlejuiceDependencyHelper.read_dependencies",
            return_value={
                # dep_1_dag has finished now, and dep_2_dag had finished in a previous run.
                "current_dag": ["dep_1_dag:task", "dep_2_dag:task"],
                "dep_2_dag": ["origin_dag:task"],
                "dep_1_dag": ["origin_dag:task"],
            },
        ):
            assert reprocessing_guard_task_creator._should_run_dag() is True
            # Check if the xcom was retrieved correctly
            mock_context["ti"].xcom_pull.assert_called_once_with(
                key="reprocessing_guard_origin_dag_dependencies",
                task_ids="reprocessing-guard",
                include_prior_dates=True,
            )
