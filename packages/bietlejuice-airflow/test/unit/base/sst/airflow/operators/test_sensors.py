"""Unit tests for SStExternalTaskSensor execution date wiring."""

from datetime import timedelta

import pytest

from bietlejuice.base.sst.airflow.operators.sensors import SStExternalTaskSensor


class TestSStExternalTaskSensorExecutionDelta:
    def test_execution_delta_is_none_when_execution_date_fn_is_passed(self):
        sensor = SStExternalTaskSensor(
            task_id="wait_for_upstream",
            external_dag_id="upstream_dag_id",
            execution_date_fn=lambda logical_date: logical_date,
        )

        assert sensor.execution_delta is None
        assert sensor.execution_date_fn is not None

    def test_execution_delta_matches_delta_hours_when_fn_not_passed(self):
        sensor = SStExternalTaskSensor(
            task_id="wait_for_upstream",
            external_dag_id="upstream_dag_id",
            delta_hours=1.5,
        )

        assert sensor.execution_delta == timedelta(hours=1.5)
        assert sensor.execution_date_fn is None

    @pytest.mark.parametrize("delta_hours", [None, 0])
    def test_execution_delta_unset_for_same_logical_date_offsets(self, delta_hours):
        sensor = SStExternalTaskSensor(
            task_id="wait_for_upstream",
            external_dag_id="upstream_dag_id",
            delta_hours=delta_hours,
        )

        if delta_hours is None:
            assert sensor.execution_delta is None
        else:
            assert sensor.execution_delta == timedelta(hours=0)
