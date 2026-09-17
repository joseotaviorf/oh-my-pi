"""Unit tests for the hourly-schedule + daily short-circuit wiring in
salesforce_api_v2.py.

Same convention as
test/unit/dags/for_rent/vocs_machina_planning/test_vocs_machina_planning.py:
import the DAG module via its dotted path (dags.<domain>.<name>.<name>),
relying on ../../conftest.py to put the repo root on sys.path, with a
real-but-inert emr_plugin installed just for the import (the cluster type is
emr_*, so job_cluster_engine lazily imports emr_plugin while the module builds
its tasks at parse time).

What these tests lock down:

- The daily gate uses ``ignore_downstream_trigger_rules=False``. This is the
  cluster-leak guard: with the ShortCircuitOperator default (True) a skipped
  hour would flat-skip every transitive downstream — including
  ``terminate-emr-cluster`` and ``end`` — leaving a live EMR cluster behind.
- The gate passes only for the run whose ``data_interval_end`` lands on
  ``daily_execution_hour``; that run processes the previous COMPLETE day
  (``macros.ds_add(data_interval_end | ds, -1)``). Gating or dating off
  ``data_interval_start`` instead would make daily objects process a day that
  is still ~23h in the future.
- Daily objects sit behind the gate; hourly objects (email_message_v2) do not,
  and they alone carry ``--partition_hour``.
"""

import inspect
import sys
from unittest.mock import MagicMock

from airflow.models import BaseOperator
from airflow.operators.empty import EmptyOperator
from airflow.utils.trigger_rule import TriggerRule

_BASE_OPERATOR_PARAMS = set(inspect.signature(BaseOperator.__init__).parameters)


def _fake_emr_operator(*args, **kwargs):
    """Real BaseOperator stand-in for one emr_plugin operator (never executed)."""
    known_kwargs = {
        key: value for key, value in kwargs.items() if key in _BASE_OPERATOR_PARAMS
    }
    return EmptyOperator(*args, **known_kwargs)


def _build_fake_emr_plugin():
    fake = MagicMock()
    fake.QuintoAndarEmrCreateClusterOperator = MagicMock(side_effect=_fake_emr_operator)
    fake.QuintoAndarEmrSubmitStepsOperator = MagicMock(side_effect=_fake_emr_operator)
    fake.QuintoAndarEmrTerminateClusterOperator = MagicMock(
        side_effect=_fake_emr_operator
    )
    fake.QuintoAndarEmrSubmitStepsOperator.build_spark_submit_step = MagicMock(
        return_value={
            "Name": "step",
            "ActionOnFailure": "CONTINUE",
            "HadoopJarStep": {},
        }
    )
    return fake


def _import_dag_module_with_fake_emr_plugin():
    """Import salesforce_api_v2.py once with inert EMR operators installed.

    Returns the module AND the fake plugin: build_spark_submit_step's recorded
    calls are the only place the per-task job parameters (partition_date /
    partition_hour argv) are observable, since the fake operators drop
    non-BaseOperator kwargs.
    """
    original_emr_plugin = sys.modules.get("emr_plugin")
    fake_plugin = _build_fake_emr_plugin()
    sys.modules["emr_plugin"] = fake_plugin
    try:
        import dags.support_and_service.salesforce_api_v2.salesforce_api_v2 as module
    finally:
        if original_emr_plugin is None:
            del sys.modules["emr_plugin"]
        else:
            sys.modules["emr_plugin"] = original_emr_plugin
    return module, fake_plugin


_module, _fake_plugin = _import_dag_module_with_fake_emr_plugin()

dag = _module.dag
DAILY_EXECUTION_HOUR = _module.DAILY_EXECUTION_HOUR
DAILY_PARTITION_DATE = _module.DAILY_PARTITION_DATE

GATE_TASK_ID = "check-hour-to-run-daily-objects"
DAILY_TABLES = ("task_v2", "case_milestone_v2", "record_type_v2", "case_feed_v2")
HOURLY_TABLES = ("email_message_v2",)

_STEP_ARGS_BY_TASK = {
    call.kwargs["name"]: call.kwargs["args"]
    for call in _fake_plugin.QuintoAndarEmrSubmitStepsOperator.build_spark_submit_step.call_args_list
}


def _argv_value(argv, flag):
    return argv[argv.index(flag) + 1] if flag in argv else None


class TestSchedule:
    def test_dag_runs_hourly(self):
        assert dag.schedule_interval == "0 * * * *"


class TestDailyGate:
    def test_gate_does_not_flat_skip_downstream_trigger_rules(self):
        gate = dag.get_task(GATE_TASK_ID)
        assert gate.ignore_downstream_trigger_rules is False

    def test_gate_passes_only_at_daily_execution_hour(self):
        gate = dag.get_task(GATE_TASK_ID)
        # data_interval_end.hour renders as a string through op_args templating.
        passing = [hour for hour in range(24) if gate.python_callable(str(hour))]
        assert passing == [DAILY_EXECUTION_HOUR]
        assert gate.python_callable(DAILY_EXECUTION_HOUR)

    def test_daily_raw_tasks_sit_behind_gate(self):
        for table in DAILY_TABLES:
            raw = dag.get_task(f"load_datalake_salesforce_raw_{table}")
            assert GATE_TASK_ID in raw.upstream_task_ids

    def test_hourly_raw_tasks_bypass_gate(self):
        for table in HOURLY_TABLES:
            raw = dag.get_task(f"load_datalake_salesforce_raw_{table}")
            assert GATE_TASK_ID not in raw.upstream_task_ids
            assert "execute-job-cluster" in raw.upstream_task_ids


class TestClusterTeardownSurvivesSkips:
    def test_terminate_runs_on_all_done(self):
        terminate = dag.get_task("terminate-emr-cluster")
        assert terminate.trigger_rule == TriggerRule.ALL_DONE

    def test_end_carried_by_terminate_success(self):
        end = dag.get_task("end_salesforce_api_v2")
        assert end.trigger_rule == TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS
        assert "terminate-emr-cluster" in end.upstream_task_ids


class TestPartitionParameters:
    def test_daily_tasks_use_previous_complete_day(self):
        assert DAILY_PARTITION_DATE == "{{ macros.ds_add(data_interval_end | ds, -1) }}"
        for table in DAILY_TABLES:
            for schema in ("datalake_salesforce_raw", "datalake_salesforce_clean"):
                argv = _STEP_ARGS_BY_TASK[f"load_{schema}_{table}"]
                assert _argv_value(argv, "--partition_date") == DAILY_PARTITION_DATE
                assert "--partition_hour" not in argv

    def test_hourly_tasks_process_their_completed_hour(self):
        for table in HOURLY_TABLES:
            for schema in ("datalake_salesforce_raw", "datalake_salesforce_clean"):
                argv = _STEP_ARGS_BY_TASK[f"load_{schema}_{table}"]
                assert (
                    _argv_value(argv, "--partition_date")
                    == "{{ data_interval_start | ds }}"
                )
                assert (
                    _argv_value(argv, "--partition_hour")
                    == "{{ data_interval_start.strftime('%H') }}"
                )
