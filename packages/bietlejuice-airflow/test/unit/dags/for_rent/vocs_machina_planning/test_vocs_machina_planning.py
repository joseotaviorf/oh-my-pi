"""Unit tests for the pure inference-status logic in vocs_machina_planning.py.

Same convention as
packages/bietlejuice-airflow/test/unit/dags/platform/dag_runtime_monitoring/test_dag_runtime_monitoring.py:
import the DAG module via its dotted path (dags.<domain>.<name>.<name>),
relying on ../../conftest.py to put the repo root on sys.path. Run as part of
`make unit-tests` (uv run --directory packages/bietlejuice-airflow pytest).

conftest.py stubs the whole databricks_plugin module as a bare MagicMock
(real Databricks deps only exist at runtime in Databricks/Composer) --
QuintoAndarDatabricksCreateClusterOperator/SubmitRunOperator/
TerminateClusterOperator therefore construct mock objects instead of real
operators when this module is imported plainly. Slice 1's create-cluster ->
submit-run -> terminate-cluster wiring is plain, un-templated ``>>``
chaining, so that never mattered. Slice 3 added
DatalakeTaskGroup.build_task_group_from_sql_files, whose internal
_build_task_group calls chain(load_table_task, metadata_sync_task) (see
datalake_task_group.py) -- and a bare MagicMock instance is not a
DependencyMixin, so that chain() call raises TypeError at DAG-parse/import
time. _import_dag_module_with_fake_databricks_operators() below swaps in a
real (if inert) BaseOperator subclass for those three names just long enough
to import the module once (imports are cached), then restores the original
MagicMock attributes so no other test file in the suite is affected
regardless of collection order.

Wrinkle discovered while wiring this up: bietlejuice.base.airflow.task_groups.
datalake_task_group does its OWN `from databricks_plugin import
QuintoAndarDatabricksSubmitRunOperator` at that module's import time. When
this test file is run in isolation, that import happens for the first time
*after* our patch is applied, so it naturally picks up the fake class. But in
a full-suite run, test_datalake_task_group.py / test_datalake_task_group_
validation.py (collected earlier, under test/unit/base/...) already import
and cache that module *before* our patch runs -- so its
QuintoAndarDatabricksSubmitRunOperator name stays bound to the original
MagicMock no matter what we set on the databricks_plugin module afterwards
(Python caches the imported module and `from X import Y` copies the
reference once, it does not re-read X.Y later). So we also
importlib.reload() that already-imported module around the patch window,
forcing it to re-bind against our fake class, then reload it again on the
way out to restore it to the original MagicMock-bound state.

Only the pure S3-key -> status mapping and skip/proceed logic is exercised
otherwise (no real or mocked S3/Databricks/Spark needed). Building `dag` at
import time also doubles as an import-cleanliness check: ConfigurationService
reads local YAML only, no network calls happen at parse time.
"""

import importlib
import inspect
import json
import sys
from datetime import date
from unittest.mock import MagicMock, patch

import pytest
from airflow.models import BaseOperator
from airflow.timetables.datasets import DatasetOrTimeSchedule
from airflow.timetables.trigger import CronTriggerTimetable

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum

_BASE_OPERATOR_PARAMS = set(inspect.signature(BaseOperator.__init__).parameters)
_DATALAKE_TASK_GROUP_MODULE_NAME = (
    "bietlejuice.base.airflow.task_groups.datalake_task_group"
)


class _FakeDatabricksOperator(BaseOperator):
    """Real BaseOperator stand-in for the mocked Databricks operators.

    Accepts (and silently drops) whatever Databricks-specific kwargs the
    real QuintoAndarDatabricks*Operator classes take (json,
    cluster_configuration, access_control_list, libraries,
    polling_period_seconds, databricks_conn_id, do_output_xcom_push, ...) --
    only params BaseOperator itself understands (task_id, dag, pool,
    execution_timeout, ...) are forwarded. Never actually executed.
    """

    def __init__(self, *args, **kwargs):
        known_kwargs = {
            key: value for key, value in kwargs.items() if key in _BASE_OPERATOR_PARAMS
        }
        super().__init__(*args, **known_kwargs)

    def execute(self, context):
        raise NotImplementedError("stub operator: not meant to run in unit tests")


def _import_dag_module_with_fake_databricks_operators():
    """Import vocs_machina_planning.py with real-but-inert Databricks operators.

    See module docstring for why this is needed (Slice 3's DatalakeTaskGroup
    enrich task group calls chain() on the built load/metadata-sync tasks at
    import time, which requires DependencyMixin instances, not bare
    MagicMocks). Restores conftest.py's original MagicMock stub afterwards.
    """
    databricks_plugin_stub = sys.modules.get("databricks_plugin")
    operator_names = [
        "QuintoAndarDatabricksCreateClusterOperator",
        "QuintoAndarDatabricksSubmitRunOperator",
        "QuintoAndarDatabricksTerminateClusterOperator",
    ]
    is_mocked = isinstance(databricks_plugin_stub, MagicMock)
    originals = {}
    datalake_task_group_module = sys.modules.get(_DATALAKE_TASK_GROUP_MODULE_NAME)
    if is_mocked:
        for name in operator_names:
            originals[name] = getattr(databricks_plugin_stub, name)
            setattr(databricks_plugin_stub, name, _FakeDatabricksOperator)
        if datalake_task_group_module is not None:
            # Already imported by an earlier-collected test (see module
            # docstring) -- its QuintoAndarDatabricksSubmitRunOperator name
            # is stale until reloaded against the patch above.
            importlib.reload(datalake_task_group_module)
    try:
        import dags.for_rent.vocs_machina_planning.vocs_machina_planning as module
    finally:
        if is_mocked:
            for name, original in originals.items():
                setattr(databricks_plugin_stub, name, original)
            if datalake_task_group_module is not None:
                importlib.reload(datalake_task_group_module)
    return module


_vocs_machina_planning = _import_dag_module_with_fake_databricks_operators()

BACKFILL_STATUS_SUMMARY_TABLE = _vocs_machina_planning.BACKFILL_STATUS_SUMMARY_TABLE
BACKFILL_STATUS_TABLE = _vocs_machina_planning.BACKFILL_STATUS_TABLE
DAG_ID = _vocs_machina_planning.DAG_ID
FONTES = _vocs_machina_planning.FONTES
SOURCE = _vocs_machina_planning.SOURCE
active_prompts = _vocs_machina_planning.active_prompts
backfill_day_range = _vocs_machina_planning.backfill_day_range
build_snapshot_rows = _vocs_machina_planning.build_snapshot_rows
dag = _vocs_machina_planning.dag
existing_marker_keys_for_days = _vocs_machina_planning.existing_marker_keys_for_days
hash_snapshot_rows = _vocs_machina_planning.hash_snapshot_rows
iter_partition_days = _vocs_machina_planning.iter_partition_days
should_skip_stage_task = _vocs_machina_planning.should_skip_stage_task
stage_inference_status_to_s3 = _vocs_machina_planning.stage_inference_status_to_s3
success_marker_key = _vocs_machina_planning.success_marker_key


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
    # (zero-padded month/day). A non-padded key here would never match a
    # listed key and every partition would report "missing", even for days
    # quintoml already finalized.
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
    stage_inference_status_to_s3 fills in via existing_marker_keys_for_days
    (batched S3Hook.list_keys, one call per unique backfill day)."""

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


def test_dag_id_and_hybrid_schedule():
    # VOCS-34 Slice 3: schedule_interval=None placeholder is gone, replaced by
    # a DatasetOrTimeSchedule (OR of FONTES) + a 6h CronTriggerTimetable
    # safety net. max_active_runs=1 so a dataset event and a cron tick can't
    # overlap.
    assert dag.dag_id == DAG_ID
    assert dag.dag_id == "bietlejuice.vocs_machina_planning"
    assert isinstance(dag.timetable, DatasetOrTimeSchedule)
    assert isinstance(dag.timetable.timetable, CronTriggerTimetable)
    assert dag.timetable.timetable._expression == "0 */6 * * *"
    assert dag.max_active_runs == 1


def test_fontes_has_the_fourteen_reverse_birdie_sources_verbatim():
    # Copied verbatim from quintoml's config/prod.yml job.schedule -- this
    # list must not be altered independently of that file.
    assert len(FONTES) == 14
    uris = [dataset.uri for dataset in FONTES]
    assert len(set(uris)) == 14
    assert all(
        uri.startswith("bietlejuice.reverse_birdie:load-reverse-") for uri in uris
    )
    assert all(uri.endswith(":first-run-of-day") for uri in uris)


def test_dag_schedule_dataset_condition_covers_all_fontes():
    # Confirms reduce(or_, FONTES) built a condition that actually references
    # all 14 datasets (not e.g. silently collapsing to one via a typo), and
    # that DatasetOrTimeSchedule accepted it without raising at DAG-parse
    # time (this test only runs because `dag` above was importable).
    dataset_uris_in_condition = {
        name for name, _ in dag.timetable.dataset_condition.iter_datasets()
    }
    assert dataset_uris_in_condition == {dataset.uri for dataset in FONTES}


def test_backfill_status_summary_load_task_id_and_dataset_uri():
    # This is the cross-repo contract quintoml's Slice 4 hardcodes verbatim:
    # bietlejuice.vocs_machina_planning:load-enrich-vocs-machina-backfill-status-summary:first-run-of-day
    # Computed the same way DatalakeTaskGroup._build_task_group computes it
    # internally (BaseTaskGroup.generate_default_task_id).
    task_id = BaseTaskGroup.generate_default_task_id(
        task_prefix=BaseTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.ENRICH,
        schema=SOURCE,
        table_name=BACKFILL_STATUS_SUMMARY_TABLE,
    )
    assert task_id == "load-enrich-vocs-machina-backfill-status-summary"

    dataset_uri = f"{DAG_ID}:{task_id}:first-run-of-day"
    assert dataset_uri == (
        "bietlejuice.vocs_machina_planning:"
        "load-enrich-vocs-machina-backfill-status-summary:first-run-of-day"
    )

    # Proves build_task_group_from_sql_files actually discovered and built
    # this table's load task on the real `dag` (not just that
    # generate_default_task_id() can format a plausible-looking string) --
    # possible now thanks to _import_dag_module_with_fake_databricks_operators,
    # which swaps in a real BaseOperator stand-in so DatalakeTaskGroup's
    # tasks self-register instead of being unregistered MagicMocks.
    detail_task_id = BaseTaskGroup.generate_default_task_id(
        task_prefix=BaseTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.ENRICH,
        schema=SOURCE,
        table_name=BACKFILL_STATUS_TABLE,
    )
    assert task_id in dag.task_ids
    assert detail_task_id in dag.task_ids


def test_backfill_status_detail_load_task_id_differs_from_summary():
    # Sanity check that the detail table's task id (which also gets an
    # auto-attached dataset outlet, see vocs_machina_planning.py's comment
    # above build_task_group_from_sql_files) is a different, unambiguous
    # string -- nothing downstream could confuse the two.
    task_id = BaseTaskGroup.generate_default_task_id(
        task_prefix=BaseTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.ENRICH,
        schema=SOURCE,
        table_name=BACKFILL_STATUS_TABLE,
    )
    assert task_id == "load-enrich-vocs-machina-backfill-status"


class TestHashSnapshotRows:
    def test_same_rows_same_order_produce_same_hash(self):
        rows = [
            {
                "day": "2026-05-01",
                "prompt_id": "p1",
                "prompt_hash": "h1",
                "inference_status": "done",
            }
        ]
        assert hash_snapshot_rows(rows) == hash_snapshot_rows(rows)

    def test_reordered_rows_produce_the_same_hash(self):
        row_a = {
            "day": "2026-05-01",
            "prompt_id": "p1",
            "prompt_hash": "h1",
            "inference_status": "done",
        }
        row_b = {
            "day": "2026-05-02",
            "prompt_id": "p2",
            "prompt_hash": "h2",
            "inference_status": "missing",
        }
        assert hash_snapshot_rows([row_a, row_b]) == hash_snapshot_rows([row_b, row_a])

    def test_different_content_produces_a_different_hash(self):
        rows = [
            {
                "day": "2026-05-01",
                "prompt_id": "p1",
                "prompt_hash": "h1",
                "inference_status": "done",
            }
        ]
        changed_rows = [{**rows[0], "inference_status": "missing"}]
        assert hash_snapshot_rows(rows) != hash_snapshot_rows(changed_rows)


class TestShouldSkipStageTask:
    """VOCS-34 Slice 3 selective propagation: the pure skip-vs-proceed
    decision, exercised mock-free per the four required scenarios."""

    def test_dataset_event_present_and_unchanged_proceeds(self):
        assert (
            should_skip_stage_task(
                triggering_dataset_events={"some:dataset:first-run-of-day": []},
                previous_snapshot_hash="abc",
                new_snapshot_hash="abc",
            )
            is False
        )

    def test_dataset_event_present_and_changed_proceeds(self):
        assert (
            should_skip_stage_task(
                triggering_dataset_events={"some:dataset:first-run-of-day": []},
                previous_snapshot_hash="abc",
                new_snapshot_hash="def",
            )
            is False
        )

    def test_no_dataset_event_and_unchanged_skips(self):
        assert (
            should_skip_stage_task(
                triggering_dataset_events={},
                previous_snapshot_hash="abc",
                new_snapshot_hash="abc",
            )
            is True
        )

    def test_no_dataset_event_and_changed_proceeds(self):
        assert (
            should_skip_stage_task(
                triggering_dataset_events={},
                previous_snapshot_hash="abc",
                new_snapshot_hash="def",
            )
            is False
        )

    def test_no_dataset_event_and_no_previous_hash_proceeds(self):
        # First run ever (Variable unset) must not be treated as "unchanged".
        assert (
            should_skip_stage_task(
                triggering_dataset_events={},
                previous_snapshot_hash=None,
                new_snapshot_hash="def",
            )
            is False
        )


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
    source = inspect.getsource(_vocs_machina_planning)
    terminate_call = source[source.index("terminate_cluster_task = ") :]
    terminate_call = terminate_call[: terminate_call.index(")\n") + 1]
    assert "trigger_rule=TriggerRule.NONE_SKIPPED" in terminate_call


class TestStageInferenceStatusToS3:
    """Regression coverage for the post-XCom-revert design: this task only
    computes the skip-vs-proceed hash and never writes to S3. The actual
    read + transform + load happens independently in
    load_vocs_machina_inference_status_raw.py, on the Databricks cluster
    this DAG creates next -- see that file's module docstring for why
    (airflow-prod-role has no S3 write grant on this repo's own datalake
    bucket, and handing the rows to Databricks via XCom/job-parameters
    instead hit Databricks' jobs/runs/submit 10,000-byte parameter cap in
    production; see the reverted bi-etl-ejuice#27353).
    """

    _MANIFEST = {
        "prompts": [
            {
                "prompt_id": "p1",
                "prompt_hash": "h1",
                "active": True,
                "backfill_days": 0,
            }
        ]
    }

    @staticmethod
    def _kwargs_with_dataset_event():
        # A non-empty triggering_dataset_events makes should_skip_stage_task
        # always proceed (see its docstring/TestShouldSkipStageTask above)
        # regardless of the hash comparison, so this test exercises the
        # Variable.set call in isolation from the skip decision.
        return {"triggering_dataset_events": {"some:dataset:first-run-of-day": []}}

    @patch("dags.for_rent.vocs_machina_planning.vocs_machina_planning.Variable")
    @patch("dags.for_rent.vocs_machina_planning.vocs_machina_planning.S3Hook")
    def test_never_writes_to_s3(self, mock_s3hook_cls, mock_variable):
        mock_hook = mock_s3hook_cls.return_value
        mock_hook.read_key.return_value = json.dumps(self._MANIFEST)
        mock_hook.list_keys.return_value = []
        mock_variable.get.return_value = None

        stage_inference_status_to_s3("2026-07-30", **self._kwargs_with_dataset_event())

        mock_hook.load_string.assert_not_called()

    @patch("dags.for_rent.vocs_machina_planning.vocs_machina_planning.Variable")
    @patch("dags.for_rent.vocs_machina_planning.vocs_machina_planning.S3Hook")
    def test_variable_set_with_the_computed_hash_when_proceeding(
        self, mock_s3hook_cls, mock_variable
    ):
        mock_hook = mock_s3hook_cls.return_value
        mock_hook.read_key.return_value = json.dumps(self._MANIFEST)
        mock_hook.list_keys.return_value = []
        mock_variable.get.return_value = None

        stage_inference_status_to_s3("2026-07-30", **self._kwargs_with_dataset_event())

        mock_variable.set.assert_called_once_with(
            _vocs_machina_planning.LAST_SNAPSHOT_HASH_VARIABLE_KEY,
            hash_snapshot_rows(
                build_snapshot_rows(
                    iter_partition_days(
                        active_prompts(self._MANIFEST), date(2026, 7, 30)
                    ),
                    existing_marker_keys=set(),
                )
            ),
        )
