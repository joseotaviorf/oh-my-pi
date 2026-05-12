"""
Regression: ``get_current_context`` after early import of the task-creator graph.

DAG-builder tests import ``TaskCreatorFactory``, which loads
``reprocessing_guard_task_creator`` at collection time. ``_should_run_dag`` must call
``get_current_context`` via ``airflow.operators.python`` (attribute lookup) so unit
tests can patch ``airflow.operators.python.get_current_context`` reliably; a
``from ... import get_current_context`` binding would ignore that patch.
"""

import importlib
from unittest import mock

import pendulum
import pytest
from airflow.exceptions import AirflowException

# Mirrors collection-time import order when workflow tests load TaskCreatorFactory.
importlib.import_module("bietlejuice.base.airflow.task_creators.task_creator_factory")
from bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator import (  # noqa: E402
    ReprocessingGuardTaskCreator,
)


def _non_reprocessing_context():
    task_instance = mock.MagicMock()
    task_instance.xcom_pull.return_value = None
    task = mock.MagicMock()
    task_instance.task = task
    task.task_id = "task"
    dag = mock.MagicMock()
    dag.dag_id = "current_dag"
    return {
        "params": {"run_type": "impact_downstream_dependents"},
        "triggering_dataset_events": {},
        "execution_date": pendulum.datetime(2025, 1, 1),
        "ti": task_instance,
        "task": task,
        "dag": dag,
    }


class TestReprocessingGuardEarlyImportContextRepro:
    def test_unpatched_should_run_dag_raises_outside_airflow_task(self):
        """Documents the failure mode when no context mock is active."""
        creator = ReprocessingGuardTaskCreator(mock.MagicMock())
        with pytest.raises(AirflowException, match="no context was found"):
            creator._should_run_dag()

    def test_should_run_dag_with_bietlejuice_module_get_current_context_patch(self):
        """Patching the consumer module still works after early import."""
        ctx = _non_reprocessing_context()
        with mock.patch(
            "bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator.airflow_python_operators.get_current_context",
            return_value=ctx,
        ):
            creator = ReprocessingGuardTaskCreator(mock.MagicMock())
            assert creator._should_run_dag() is True

    def test_should_run_dag_with_airflow_module_get_current_context_patch(self):
        """Preferred: patch Airflow's ``get_current_context`` after early import."""
        ctx = _non_reprocessing_context()
        with mock.patch(
            "airflow.operators.python.get_current_context",
            return_value=ctx,
        ):
            creator = ReprocessingGuardTaskCreator(mock.MagicMock())
            assert creator._should_run_dag() is True
