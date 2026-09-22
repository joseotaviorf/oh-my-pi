"""Unit tests for the ``backfill_tables`` conf contract of ``dw_bpo_performance``.

The whole feature lives in Jinja inside
``dags/planning_and_performance/dw_bpo_performance/dw_bpo_performance_declaration.yml``:
per-table ``extra_query_template_params`` widen the load window, and
``when_not_matched_by_source_delete_condition`` turns the daily upsert into a
delete-and-reinsert carried by the same Delta MERGE. Nothing in the packages
changed, so there is no Python unit to exercise -- what can break is the
rendering, and that is what these tests pin.

They read the real declaration (so the tests fail if the YAML drifts) and render
its templates through a real ``airflow.DAG``'s Jinja environment, with the real
``BaseWorkflow.get_date_param`` registered as the user-defined macro exactly as
``BaseWorkflow.dag_instance`` does. Building the DAG object itself is deliberately
avoided: ``databricks_plugin`` is a MagicMock in this suite (see
``test/unit/conftest.py``), so every Spark task would be a MagicMock and
``task.json`` would assert nothing real.
"""

import json
from pathlib import Path

import pytest
import yaml
from airflow import DAG
from airflow.utils import timezone

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)

_REPO_ROOT = Path(__file__).resolve().parents[7]
_DECLARATION = (
    _REPO_ROOT
    / "dags"
    / "planning_and_performance"
    / "dw_bpo_performance"
    / "dw_bpo_performance_declaration.yml"
)

# The only tables that MERGE, and therefore the only ones a reset applies to.
INCREMENTAL_TABLES = [
    "cases_perspective",
    "segments_perspective",
    "satisfaction_salesforce",
    "customer_contacts_session",
]

DATA_INTERVAL_START = timezone.datetime(2026, 9, 1)
DEFAULT_START = "2026-09-01"
DEFAULT_END = "2026-09-02"  # the declaration offsets load_end_date by +1 day
ALL_TIME_START = "1970-01-01"
ALL_TIME_END = "2999-12-31"

DAILY = (DEFAULT_START, DEFAULT_END, "")
RESET = (ALL_TIME_START, ALL_TIME_END, "TRUE")


@pytest.fixture(scope="module")
def tables_customization() -> dict:
    declaration = yaml.safe_load(_DECLARATION.read_text())
    return declaration["workflow"]["tables_customization"]


class _FakeDagRun:
    """Stands in for the DagRun; the templates only ever read ``.conf``."""

    def __init__(self, conf):
        self.conf = conf


@pytest.fixture(scope="module")
def jinja_env():
    """Airflow's own Jinja env, with the production ``get_date_param`` macro.

    ``get_date_param`` is an unbound method that never touches ``self``, so
    binding it to ``None`` exercises the real implementation rather than a copy.
    """
    dag = DAG(
        dag_id="test_dw_bpo_performance_rendering",
        start_date=DATA_INTERVAL_START,
        schedule=None,
        user_defined_macros={
            "get_date_param": lambda *args: BaseWorkflow.get_date_param(None, *args)
        },
    )
    return dag.get_template_env()


def _render(jinja_env, template: str, conf) -> str:
    import airflow.macros

    return jinja_env.from_string(template).render(
        dag_run=_FakeDagRun(conf),
        data_interval_start=DATA_INTERVAL_START,
        macros=airflow.macros,
    )


def _render_table(jinja_env, customization: dict, conf) -> tuple:
    """Returns the (load_start_date, load_end_date, delete_condition) triple."""
    params = customization["extra_query_template_params"]
    return (
        _render(jinja_env, params["load_start_date"], conf),
        _render(jinja_env, params["load_end_date"], conf),
        _render(
            jinja_env,
            customization["when_not_matched_by_source_delete_condition"],
            conf,
        ),
    )


@pytest.mark.parametrize(
    "conf",
    [None, {}, {"backfill_tables": []}, {"backfill_tables": None}],
    ids=["no_conf", "empty_conf", "empty_list", "explicit_null"],
)
@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_run_without_a_table_list_is_unchanged(
    jinja_env, tables_customization, table, conf
):
    # conf is None on scheduled and dataset-triggered runs. The window must stay
    # the one-day interval the DAG has always used, and no delete clause may be
    # emitted -- an accidental TRUE here would wipe history on every daily run.
    # An empty or null list must behave the same: there is deliberately no
    # "reset everything" shorthand, so nothing is a safe default.
    assert _render_table(jinja_env, tables_customization[table], conf) == DAILY


@pytest.mark.parametrize("selected", INCREMENTAL_TABLES)
def test_naming_a_table_resets_only_that_table(
    jinja_env, tables_customization, selected
):
    conf = {"backfill_tables": [selected]}

    for table in INCREMENTAL_TABLES:
        expected = RESET if table == selected else DAILY
        assert _render_table(jinja_env, tables_customization[table], conf) == expected


def test_several_tables_can_be_reset_in_one_run(jinja_env, tables_customization):
    conf = {"backfill_tables": ["segments_perspective", "cases_perspective"]}

    for table in INCREMENTAL_TABLES:
        expected = RESET if table in conf["backfill_tables"] else DAILY
        assert _render_table(jinja_env, tables_customization[table], conf) == expected


def test_all_four_tables_can_be_reset_explicitly(jinja_env, tables_customization):
    conf = {"backfill_tables": list(INCREMENTAL_TABLES)}

    for table in INCREMENTAL_TABLES:
        assert _render_table(jinja_env, tables_customization[table], conf) == RESET


@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_a_bare_string_is_treated_as_one_table_name(
    jinja_env, tables_customization, table
):
    # Jinja's `in` on a string is substring matching, which would make
    # "segments_perspective_old" match "segments_perspective". The declaration
    # coerces a string to a single-element list so the comparison stays exact.
    conf = {"backfill_tables": table}

    for other in INCREMENTAL_TABLES:
        expected = RESET if other == table else DAILY
        assert _render_table(jinja_env, tables_customization[other], conf) == expected


@pytest.mark.parametrize(
    "requested",
    [
        ["segments_perspectiv"],
        ["segments_perspective_old"],
        ["backlog_metric"],
        "segments_perspective_old",
        "segments_perspective,cases_perspective",
    ],
    ids=["typo", "superstring", "full_load_table", "bare_superstring", "csv_string"],
)
@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_names_that_do_not_match_exactly_reset_nothing(
    jinja_env, tables_customization, table, requested
):
    # Documented trade-off: the selection is a Jinja membership test, not a
    # validated enum, so anything that is not an exact table name resets
    # nothing instead of failing the run. `superstring` and `bare_superstring`
    # are the substring-matching regression guards; `csv_string` documents that
    # a comma-separated string is not parsed -- pass a real list.
    conf = {"backfill_tables": requested}

    assert _render_table(jinja_env, tables_customization[table], conf) == DAILY


@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_manual_window_override_still_works(jinja_env, tables_customization, table):
    # The pre-existing load_start_date / load_end_date trigger-form params must
    # keep working, and must not imply a delete.
    conf = {"load_start_date": "2026-01-01", "load_end_date": "2026-01-05"}

    assert _render_table(jinja_env, tables_customization[table], conf) == (
        "2026-01-01",
        "2026-01-05",
        "",
    )


@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_backfill_bounds_are_overridable(jinja_env, tables_customization, table):
    conf = {
        "backfill_tables": [table],
        "backfill_floor_date": "2024-01-01",
        "backfill_ceiling_date": "2026-12-31",
    }

    assert _render_table(jinja_env, tables_customization[table], conf) == (
        "2024-01-01",
        "2026-12-31",
        "TRUE",
    )


@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_bounds_are_ignored_for_a_table_that_was_not_named(
    jinja_env, tables_customization, table
):
    conf = {"backfill_tables": [], "backfill_floor_date": "2024-01-01"}

    assert _render_table(jinja_env, tables_customization[table], conf) == DAILY


@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_rendered_delete_condition_survives_the_json_transport(
    jinja_env, tables_customization, table
):
    # LoadDeltaTableTaskCreator json.dumps() the raw template, Airflow renders the
    # resulting string, then load_delta_table.py json.loads() it back. Single
    # quotes in the template are what keep that round-trip intact: a double quote
    # would land as \" inside the JSON string and break the template.
    template = tables_customization[table][
        "when_not_matched_by_source_delete_condition"
    ]
    assert '"' not in template

    for conf, expected in [(None, ""), ({"backfill_tables": [table]}, "TRUE")]:
        transported = _render(jinja_env, json.dumps(template), conf)
        assert json.loads(transported) == expected


@pytest.mark.parametrize("table", INCREMENTAL_TABLES)
def test_incremental_tables_have_a_backfill_sized_timeout(tables_customization, table):
    # An all-time MERGE rewrites the whole table and will not finish inside
    # BaseTaskCreator._DEFAULT_EXECUTION_TIMEOUT_HOURS (2h). The value is static
    # because execution_timeout is resolved at DAG-build time and is not a
    # template field, so it cannot be driven from dag_run.conf.
    assert tables_customization[table]["execution_timeout_hours"] == 6


def test_full_tables_are_untouched_by_the_feature(tables_customization):
    # The blast radius is exactly the four MERGE tables: every `full` table keeps
    # inheriting the DAG-level window and the default timeout, so naming one in
    # backfill_tables cannot change how it loads.
    full_tables = {
        name: customization
        for name, customization in tables_customization.items()
        if name not in INCREMENTAL_TABLES
    }
    assert len(full_tables) == 21

    for name, customization in full_tables.items():
        assert customization["extraction_type"] == "full", name
        assert "extra_query_template_params" not in customization, name
        assert "when_not_matched_by_source_delete_condition" not in customization, name
        assert "execution_timeout_hours" not in customization, name


def test_dag_level_window_is_the_untouched_daily_one():
    declaration = yaml.safe_load(_DECLARATION.read_text())
    params = declaration["workflow"]["extra_query_template_params"]

    assert params["load_start_date"] == (
        "{{ get_date_param(dag_run, data_interval_start | ds, 'load_start_date') }}"
    )
    assert params["load_end_date"] == (
        "{{ get_date_param(dag_run, macros.ds_add(data_interval_start | ds, 1), "
        "'load_end_date') }}"
    )


def test_no_boolean_gate_remains_in_the_declaration():
    # The reset used to need `all_time_backfill: true` alongside the list. The
    # list is now the only control; this pins the simplification so a stale
    # doc snippet or template cannot reintroduce a second, silent condition.
    assert "all_time_backfill" not in _DECLARATION.read_text()
