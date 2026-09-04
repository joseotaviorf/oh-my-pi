from datetime import date

import pytest

from lineage import Hop
from query import (
    LOOKUP_TASK,
    QUERY_ROW_LIMIT,
    QueryError,
    build_inventory_sql,
    build_task_seed_tables_sql,
    build_upstream_runtime_sql,
)

SEED_JOBS = (
    (
        "bietlejuice.load-dw-rent-fact-contracts",
        "load-dw-rent-fact-contracts",
        "dw_rent.fact_contracts",
    ),
)


def _table_sql(max_hop_level=None, job_hops=None, include_before_d0=False):
    return build_upstream_runtime_sql(
        date(2026, 8, 18),
        date(2026, 8, 24),
        SEED_JOBS,
        max_hop_level=max_hop_level,
        job_hops=job_hops,
        include_before_d0=include_before_d0,
    )


def test_table_mode_includes_inventory_and_success_attempts():
    sql = _table_sql()
    assert "('bietlejuice.load-dw-rent-fact-contracts', " in sql
    assert "'load-dw-rent-fact-contracts', 'dw_rent.fact_contracts')" in sql
    assert 'hive.datalake_dag_inventory_clean."table"' in sql
    assert "bietlejuice_table_dependencies_with_indirection" not in sql
    assert "hive.datalake_astro_clean.task_instance" in sql
    assert "task_instance_history" not in sql
    assert "UNION ALL" not in sql
    assert "ti.task_state = 'success'" in sql
    assert "0 AS level" in sql
    assert "c.ts_ended <= sd.seed_ts_started" in sql
    assert "ut.table_name" in sql
    assert "lr.latest_ts_started" in sql
    assert "lr.latest_ts_ended" in sql
    assert "approx_percentile(" in sql
    assert "qty_runs" not in sql
    assert "modal_state" not in sql
    assert "ORDER BY lr.latest_ts_started, table_name" in sql
    assert "year BETWEEN 2026 AND 2026" in sql
    assert (
        "(ti.year * 10000 + ti.month * 100 + ti.day) BETWEEN 20260817 AND 20260825"
    ) in sql
    assert (
        "CAST(ti.ts_started AS DATE) BETWEEN DATE '2026-08-18' AND DATE '2026-08-24'"
    ) in sql
    assert f"LIMIT {QUERY_ROW_LIMIT}" in sql
    assert "MAKE_DATE" not in sql


def test_run_day_is_utc_calendar_day_of_ts_started():
    sql = _table_sql()
    assert "CAST(MIN(ti.ts_started) AS DATE) AS run_day" in sql
    assert "MAX(ti.year * 10000 + ti.month * 100 + ti.day)" not in sql
    assert "PARTITION BY id_dag, id_task, run_day" in sql
    assert "GROUP BY run_day" in sql


def test_run_selection_never_compares_id_run_as_a_clock():
    sql = _table_sql()
    assert "successor_id_run" not in sql
    assert "s.id_run < " not in sql
    assert "ORDER BY c.ts_started DESC, c.id_run DESC" in sql
    assert "ORDER BY ts_started DESC, id_run DESC" in sql
    assert "ORDER BY partition_key DESC, id_run DESC" not in sql


def test_cutoff_is_per_seed_day_not_one_global_instant():
    sql = _table_sql()
    assert "successor_ts_started" not in sql
    assert "MAX(ts_started) AS seed_ts_started" in sql
    assert "CROSS JOIN seed_days AS sd" in sql
    assert "PARTITION BY c.id_dag, c.id_task, sd.run_day" in sql
    assert "OR (c.level > 0 AND c.ts_ended <= sd.seed_ts_started)" in sql


def test_seed_rows_are_picked_within_their_own_day():
    sql = _table_sql()
    assert "WHERE (c.level = 0 AND c.run_day = sd.run_day)" in sql


def test_latest_bar_and_median_share_one_selection_rule():
    sql = _table_sql()
    assert sql.count("    FROM daily_pick\n") == 2


def test_first_run_of_day_hop_drops_later_slots_of_the_day():
    sql = _table_sql(
        job_hops={
            ("bietlejuice.ebdb_partner", "load-clean-partner-agent"): Hop(
                3, first_run_of_day=True
            ),
        }
    )
    assert "ORDER BY ts_started ASC, id_run ASC" in sql
    assert "        ) AS day_rank\n" in sql
    assert "    WHERE ut.level = 0\n        OR NOT ut.first_run_of_day\n" in sql
    assert "        OR dr.day_rank = 1\n" in sql
    assert "'load-clean-partner-agent', 3, TRUE)" in sql


def test_run_specific_hop_keeps_every_slot_of_the_day():
    sql = _table_sql(
        job_hops={
            ("bietlejuice.enrich_chatbot", "load-enrich-sessions"): Hop(
                1, first_run_of_day=False
            ),
        }
    )
    assert "'load-enrich-sessions', 1, FALSE)" in sql


def test_seed_leg_is_never_first_run_of_day_gated():
    sql = _table_sql()
    assert "FALSE AS first_run_of_day" in sql
    assert "    ut.first_run_of_day,\n" in sql


def test_seed_jobs_are_literal_pairs_not_independent_mins():
    sql = build_upstream_runtime_sql(
        date(2026, 8, 18),
        date(2026, 8, 24),
        (
            ("bietlejuice.dag_a", "task_a", "shared.table"),
            ("bietlejuice.dag_b", "task_b", "shared.table"),
        ),
    )
    assert "producer_map" not in sql
    assert "MIN(inv.dag)" not in sql
    assert "MIN(inv.task)" not in sql
    assert "('bietlejuice.dag_a', 'task_a', 'shared.table')" in sql
    assert "('bietlejuice.dag_b', 'task_b', 'shared.table')" in sql
    assert "task_table_map AS" in sql


def test_unrestricted_sql_has_no_trino_hop_cap():
    sql = _table_sql(max_hop_level=None)
    assert "hops.level <=" not in sql


def test_partition_filter_spans_year_boundary():
    sql = build_upstream_runtime_sql(
        date(2025, 12, 20),
        date(2026, 1, 10),
        SEED_JOBS,
    )
    assert "year BETWEEN 2025 AND 2026" in sql
    assert (
        "(ti.year * 10000 + ti.month * 100 + ti.day) BETWEEN 20251219 AND 20260111"
    ) in sql


def test_escapes_single_quote_in_seed_jobs():
    sql = build_upstream_runtime_sql(
        date(2026, 1, 1),
        date(2026, 1, 2),
        (("bietlejuice.foo'bar", "task'id", "table'name"),),
    )
    assert "('bietlejuice.foo''bar', 'task''id', 'table''name')" in sql


def test_rejects_empty_seed_jobs():
    with pytest.raises(QueryError, match="No DAG inventory row"):
        build_upstream_runtime_sql(
            date(2026, 1, 1),
            date(2026, 1, 2),
            (),
        )


def test_rejects_end_before_start():
    with pytest.raises(QueryError, match="End date"):
        build_upstream_runtime_sql(
            date(2026, 1, 2),
            date(2026, 1, 1),
            SEED_JOBS,
        )


def test_rejects_window_longer_than_30_days():
    with pytest.raises(QueryError, match="at most 30 days"):
        build_upstream_runtime_sql(
            date(2026, 1, 1),
            date(2026, 1, 31),
            SEED_JOBS,
        )


def test_allows_30_day_inclusive_window():
    sql = build_upstream_runtime_sql(
        date(2026, 1, 1),
        date(2026, 1, 30),
        SEED_JOBS,
    )
    assert "DATE '2026-01-01'" in sql
    assert "DATE '2026-01-30'" in sql


def test_rejects_hop_level_below_one():
    with pytest.raises(QueryError, match="Max hop level"):
        build_upstream_runtime_sql(
            date(2026, 1, 1),
            date(2026, 1, 2),
            SEED_JOBS,
            max_hop_level=0,
        )


def test_job_hops_are_unioned_into_the_graph():
    sql = build_upstream_runtime_sql(
        date(2026, 8, 18),
        date(2026, 8, 24),
        (
            (
                "bietlejuice.enrich_agents_matias",
                "load-enrich-eval-session-bundle",
                "datalake_agents_matias.eval_session_bundle",
            ),
        ),
        job_hops={
            ("bietlejuice.enrich_chatbot", "load-enrich-sessions"): Hop(
                1, first_run_of_day=True
            ),
            ("bietlejuice.langfuse", "load-clean-traces"): Hop(
                2, first_run_of_day=True
            ),
        },
    )
    assert "job_hops (id_dag, id_task, level, first_run_of_day)" in sql
    assert "('bietlejuice.enrich_chatbot', 'load-enrich-sessions', 1, TRUE)" in sql
    assert "('bietlejuice.langfuse', 'load-clean-traces', 2, TRUE)" in sql


def test_no_job_hops_leg_without_job_hops():
    assert "job_hops" not in _table_sql()


def test_task_seed_query_targets_dag_inventory():
    sql = build_task_seed_tables_sql("load-dw-rent-fact-contracts")
    assert 'hive.datalake_dag_inventory_clean."table"' in sql
    assert "inv.task = 'load-dw-rent-fact-contracts'" in sql


def test_inventory_query_projects_job_keys():
    sql = build_inventory_sql()
    assert "inv.dag AS id_dag" in sql
    assert "inv.task AS id_task" in sql
    assert 'inv."table" AS table_name' in sql
    assert "inv.files_location" in sql


def test_task_seed_query_rejects_empty_task():
    with pytest.raises(QueryError, match="Lookup value is required"):
        build_task_seed_tables_sql("   ")


def test_default_sql_drops_upstreams_that_ended_before_d0():
    sql = _table_sql()
    assert "seed_anchor AS (" in sql
    assert "CAST(lr.latest_ts_ended AS DATE) >= sa.d0" in sql
    assert "CROSS JOIN seed_anchor AS sa" in sql
    assert "WHERE ut.level = 0" in sql


def test_include_before_d0_omits_the_anchor_filter():
    sql = _table_sql(include_before_d0=True)
    assert "seed_anchor" not in sql
    assert "CAST(lr.latest_ts_ended AS DATE) >= sa.d0" not in sql


def test_lookup_task_constant_is_stable():
    assert LOOKUP_TASK == "task_id"
