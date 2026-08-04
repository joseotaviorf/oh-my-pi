"""Unit tests for the pure inference-status logic in vocs_machina_planning.py.

Same convention as
packages/bietlejuice-airflow/test/unit/dags/platform/dag_runtime_monitoring/test_dag_runtime_monitoring.py:
import the DAG module via its dotted path (dags.<domain>.<name>.<name>),
relying on ../../conftest.py to put the repo root on sys.path. Run as part of
`make unit-tests` (uv run --directory packages/bietlejuice-airflow pytest),
which is a shared uv workspace environment that also has databricks_plugin
(bietlejuice-airflow-operators) installed, so importing the full DAG module
(and therefore building the real `dag` object) works here.

Only the pure S3-key -> status mapping logic is exercised (no real or mocked
S3/Databricks/Spark needed), per VOCS-34 Slice 1's verification scope.
Building `dag` at import time also doubles as an import-cleanliness check:
ConfigurationService reads local YAML only, no network calls happen at parse
time.
"""

import inspect
from datetime import date

import pytest

from dags.for_rent.vocs_machina_planning import vocs_machina_planning
from dags.for_rent.vocs_machina_planning.vocs_machina_planning import (
    DAG_ID,
    active_prompts,
    backfill_day_range,
    build_snapshot_rows,
    dag,
    existing_marker_keys_for_days,
    iter_partition_days,
    success_marker_key,
)


class FakeS3Hook:
    """Records list_keys calls instead of hitting S3 -- enough to verify
    existing_marker_keys_for_days batches by unique day rather than issuing
    one call per (day, prompt_id, prompt_hash) tuple."""

    def __init__(self, keys_by_prefix):
        self.keys_by_prefix = keys_by_prefix
        self.list_keys_calls = []

    def list_keys(self, bucket_name, prefix):
        self.list_keys_calls.append((bucket_name, prefix))
        return self.keys_by_prefix.get(prefix, [])


def test_active_prompts_filters_inactive():
    manifest = {
        "prompts": [
            {"prompt_id": "p1", "active": True},
            {"prompt_id": "p2", "active": False},
            {"prompt_id": "p3", "active": True},
        ]
    }
    assert [p["prompt_id"] for p in active_prompts(manifest)] == ["p1", "p3"]


def test_active_prompts_empty_manifest():
    assert active_prompts({}) == []
    assert active_prompts({"prompts": []}) == []


def test_active_prompts_only_accepts_literal_true():
    # quintoml's write_manifest() always writes a real JSON boolean, but a
    # hand-edited manifest could carry a truthy-but-wrong value -- the string
    # "false" is truthy in Python, so a bare `if prompt.get("active")` check
    # would wrongly treat it as active. Checking identity against True keeps
    # anything other than a literal true excluded.
    manifest = {
        "prompts": [
            {"prompt_id": "p_true", "active": True},
            {"prompt_id": "p_false_string", "active": "false"},
            {"prompt_id": "p_zero", "active": 0},
            {"prompt_id": "p_none", "active": None},
        ]
    }
    assert [p["prompt_id"] for p in active_prompts(manifest)] == ["p_true"]


def test_backfill_day_range_is_inclusive():
    today = date(2026, 7, 30)
    days = backfill_day_range(today, 2)
    assert days == [date(2026, 7, 28), date(2026, 7, 29), date(2026, 7, 30)]


def test_backfill_day_range_zero_days_is_today_only():
    today = date(2026, 7, 30)
    assert backfill_day_range(today, 0) == [today]


def test_backfill_day_range_rejects_negative():
    with pytest.raises(ValueError):
        backfill_day_range(date(2026, 7, 30), -1)


def test_success_marker_key_zero_pads_month_and_day():
    # Regression: must match quintoml's vocs_machina/storage.py
    # build_partition_prefix + build_success_marker_uri byte-for-byte
    # (zero-padded month/day). A non-padded key here would make every
    # check_for_key() call return False and every partition report "missing",
    # even for days quintoml already finalized.
    key = success_marker_key("nps_churn", "abc123", date(2026, 5, 3))
    assert key == (
        "post-contract/vocs-machina/raw/"
        "year=2026/month=05/day=03/"
        "prompt_id=nps_churn/prompt_hash=abc123/_SUCCESS"
    )


def test_iter_partition_days_expands_each_active_prompt():
    prompts = [
        {"prompt_id": "p1", "prompt_hash": "h1", "backfill_days": 1},
        {"prompt_id": "p2", "prompt_hash": "h2", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    partition_days = iter_partition_days(prompts, today)
    assert partition_days == [
        (date(2026, 7, 29), "p1", "h1"),
        (date(2026, 7, 30), "p1", "h1"),
        (date(2026, 7, 30), "p2", "h2"),
    ]


def test_iter_partition_days_skips_prompt_missing_backfill_days():
    # Regression: one manifest entry missing "backfill_days" used to raise
    # KeyError and abort the whole snapshot for every active prompt.
    prompts = [
        {"prompt_id": "p1", "prompt_hash": "h1"},
        {"prompt_id": "p2", "prompt_hash": "h2", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    assert iter_partition_days(prompts, today) == [(today, "p2", "h2")]


def test_iter_partition_days_skips_prompt_with_negative_backfill_days():
    prompts = [
        {"prompt_id": "p1", "prompt_hash": "h1", "backfill_days": -1},
        {"prompt_id": "p2", "prompt_hash": "h2", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    assert iter_partition_days(prompts, today) == [(today, "p2", "h2")]


def test_iter_partition_days_all_malformed_yields_empty_list():
    prompts = [{"prompt_id": "p1", "prompt_hash": "h1"}]
    assert iter_partition_days(prompts, date(2026, 7, 30)) == []


def test_iter_partition_days_skips_prompt_missing_prompt_id_or_hash():
    # Same "one malformed entry should not stop everyone else" treatment as
    # a missing/invalid backfill_days: a manifest entry missing prompt_id or
    # prompt_hash outright is skipped with a warning, not fatal.
    prompts = [
        {"prompt_hash": "h_bad", "backfill_days": 0},  # missing prompt_id
        {"prompt_id": "p_bad", "backfill_days": 0},  # missing prompt_hash
        {"prompt_id": "p_ok", "prompt_hash": "h_ok", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    assert iter_partition_days(prompts, today) == [(today, "p_ok", "h_ok")]


def test_iter_partition_days_skips_prompt_id_unsafe_for_s3_partition_keys():
    # A literal "/" would inject extra path segments into the
    # year=/month=/day=/prompt_id=/prompt_hash=/ structure, and a control
    # character (e.g. a null byte) is likewise rejected outright.
    prompts = [
        {"prompt_id": "nps/../evil", "prompt_hash": "h1", "backfill_days": 0},
        {"prompt_id": "bad\x00id", "prompt_hash": "h1", "backfill_days": 0},
        {"prompt_id": "p_ok", "prompt_hash": "h1", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    assert iter_partition_days(prompts, today) == [(today, "p_ok", "h1")]


def test_iter_partition_days_deduplicates_repeated_partitions():
    # Two manifest entries describing the same (prompt_id, prompt_hash) --
    # e.g. a duplicated entry with a different backfill_days -- must not
    # produce the same (day, prompt_id, prompt_hash) row twice.
    prompts = [
        {"prompt_id": "p1", "prompt_hash": "h1", "backfill_days": 2},
        {"prompt_id": "p1", "prompt_hash": "h1", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    partition_days = iter_partition_days(prompts, today)
    assert partition_days == [
        (date(2026, 7, 28), "p1", "h1"),
        (date(2026, 7, 29), "p1", "h1"),
        (date(2026, 7, 30), "p1", "h1"),
    ]


class TestExistingMarkerKeysForDays:
    """existing_marker_keys_for_days batches by unique day: one S3Hook.list_keys
    call per distinct backfill day, not one check_for_key call per
    (day, prompt_id, prompt_hash) tuple."""

    def test_one_list_keys_call_per_unique_day(self):
        day1, day2 = date(2026, 5, 1), date(2026, 5, 2)
        prefix1 = "post-contract/vocs-machina/raw/year=2026/month=05/day=01/"
        prefix2 = "post-contract/vocs-machina/raw/year=2026/month=05/day=02/"
        hook = FakeS3Hook(
            keys_by_prefix={
                prefix1: [f"{prefix1}prompt_id=p1/prompt_hash=h1/_SUCCESS"],
                prefix2: [],
            }
        )

        existing = existing_marker_keys_for_days(hook, [day1, day2])

        assert hook.list_keys_calls == [
            ("data-science.s3.data.quintoandar.com.br", prefix1),
            ("data-science.s3.data.quintoandar.com.br", prefix2),
        ]
        assert existing == {f"{prefix1}prompt_id=p1/prompt_hash=h1/_SUCCESS"}

    def test_shared_day_across_prompts_issues_a_single_call(self):
        # Two prompts sharing the same backfill day must not each trigger
        # their own S3 call -- that's the whole point of batching by day.
        day = date(2026, 5, 1)
        prefix = "post-contract/vocs-machina/raw/year=2026/month=05/day=01/"
        hook = FakeS3Hook(keys_by_prefix={prefix: []})

        existing_marker_keys_for_days(hook, [day])

        assert len(hook.list_keys_calls) == 1

    def test_ignores_non_success_keys_under_the_same_prefix(self):
        day = date(2026, 5, 1)
        prefix = "post-contract/vocs-machina/raw/year=2026/month=05/day=01/"
        hook = FakeS3Hook(
            keys_by_prefix={
                prefix: [
                    f"{prefix}prompt_id=p1/prompt_hash=h1/_SUCCESS",
                    f"{prefix}prompt_id=p1/prompt_hash=h1/part-00000.json",
                ]
            }
        )

        existing = existing_marker_keys_for_days(hook, [day])

        assert existing == {f"{prefix}prompt_id=p1/prompt_hash=h1/_SUCCESS"}

    def test_no_days_issues_no_calls(self):
        hook = FakeS3Hook(keys_by_prefix={})
        assert existing_marker_keys_for_days(hook, []) == set()
        assert hook.list_keys_calls == []


class TestBuildSnapshotRows:
    """The pure function that decides done vs missing given a set of existing
    keys -- no S3/moto involved, matching the "existing_marker_keys" contract
    stage_inference_status_to_s3 fills in by calling S3Hook.check_for_key."""

    def test_marks_done_when_marker_key_present(self):
        day = date(2026, 5, 3)
        partition_days = [(day, "nps_churn", "abc123")]
        existing = {success_marker_key("nps_churn", "abc123", day)}

        rows = build_snapshot_rows(partition_days, existing)

        assert rows == [
            {
                "day": "2026-05-03",
                "prompt_id": "nps_churn",
                "prompt_hash": "abc123",
                "inference_status": "done",
            }
        ]

    def test_marks_missing_when_marker_key_absent(self):
        day = date(2026, 5, 3)
        partition_days = [(day, "nps_churn", "abc123")]

        rows = build_snapshot_rows(partition_days, existing_marker_keys=set())

        assert rows[0]["inference_status"] == "missing"

    def test_mixed_done_and_missing(self):
        done_day = date(2026, 5, 1)
        missing_day = date(2026, 5, 2)
        partition_days = [
            (done_day, "p1", "h1"),
            (missing_day, "p1", "h1"),
        ]
        existing = {success_marker_key("p1", "h1", done_day)}

        rows = build_snapshot_rows(partition_days, existing)

        by_day = {row["day"]: row["inference_status"] for row in rows}
        assert by_day["2026-05-01"] == "done"
        assert by_day["2026-05-02"] == "missing"

    def test_unrelated_existing_keys_do_not_cause_false_positives(self):
        day = date(2026, 5, 3)
        partition_days = [(day, "nps_churn", "abc123")]
        # Keys for a different prompt/day must not mark this partition done.
        existing = {success_marker_key("other_prompt", "zzz", day)}

        rows = build_snapshot_rows(partition_days, existing)

        assert rows[0]["inference_status"] == "missing"


def test_dag_id_and_placeholder_schedule():
    assert dag.dag_id == DAG_ID
    assert dag.dag_id == "bietlejuice.vocs_machina_planning"
    assert dag.schedule_interval is None


def test_dag_has_stage_inference_status_task():
    # packages/bietlejuice-airflow/test/unit/conftest.py stubs the whole
    # databricks_plugin module with a MagicMock (real Databricks deps are only
    # available at runtime in Databricks/Composer, not in this unit test env).
    # QuintoAndarDatabricksCreateClusterOperator/SubmitRunOperator/
    # TerminateClusterOperator therefore construct mock objects here instead of
    # real operators, so they never self-register on `dag` the way a real
    # BaseOperator would -- only the plain PythonOperator task is verifiable
    # from this suite. The create-cluster -> load -> terminate wiring itself
    # is plain, un-templated `>>` chaining (see vocs_machina_planning.py) and
    # is not re-asserted here.
    assert "stage-inference-status-to-s3" in dag.task_ids
    stage_task = dag.get_task("stage-inference-status-to-s3")
    assert stage_task.op_kwargs["load_start_date"] == (
        "{{ get_date_param(dag_run, data_interval_start | ds, 'load_start_date') }}"
    )


def test_terminate_cluster_task_uses_none_skipped_trigger_rule():
    # Regression: the default ALL_SUCCESS trigger_rule left the Databricks
    # cluster running whenever an upstream task failed. Asserted on source
    # rather than the mocked `terminate_cluster_task` object itself: per
    # test_dag_has_stage_inference_status_task's note above,
    # QuintoAndarDatabricksTerminateClusterOperator is a MagicMock in this
    # unit test env (conftest.py stubs the whole databricks_plugin module
    # with ONE shared MagicMock for the whole test session), so its
    # `.call_args` reflects whichever DAG test module happened to construct
    # a terminate-cluster operator last -- not reliably this DAG's call.
    source = inspect.getsource(vocs_machina_planning)
    terminate_call = source[source.index("terminate_cluster_task = ") :]
    terminate_call = terminate_call[: terminate_call.index(")\n") + 1]
    assert "trigger_rule=TriggerRule.NONE_SKIPPED" in terminate_call
