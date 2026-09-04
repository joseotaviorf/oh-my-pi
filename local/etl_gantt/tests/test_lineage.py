from pathlib import Path

import pandas as pd

from lineage import (
    Hop,
    InventoryRow,
    JobGraph,
    ProducerEdge,
    build_job_graph,
    frame_without_excluded_layers,
    lookup_inventory_rows,
    parse_dependency_entry,
    scan_declaration,
    upstream_job_hops,
)

DECLARATION = """---
dag:
  name: enrich_agents_matias
  owner: Data Agents
  schedule_interval: 0 4 * * *
workflow:
  type: query_delta
  layer: enrich
  inner_dependencies:
    matias_session_summary:
      - eval_session_bundle
"""

PRODUCER_DECLARATION = """---
dag:
  name: enrich_chatbot
workflow:
  type: query_delta
  layer: enrich
"""

CLEAN_DECLARATION = """---
dag:
  name: langfuse
workflow:
  type: query_delta
  layer: clean
"""

DEPENDENCIES = """---
bietlejuice.enrich_agents_matias:
  - bietlejuice.enrich_chatbot:load-enrich-sessions:first-run-of-day
  - quintoml.chatbot.wall_e.inference:first-run-of-day
bietlejuice.enrich_chatbot:
  - bietlejuice.langfuse:load-clean-traces:first-run-of-day
"""

MIXED_DEPENDENCIES = """---
bietlejuice.enrich_chatbot:
  - bietlejuice.langfuse:load-clean-traces:first-run-of-day
  - bietlejuice.langfuse:load-clean-traces
"""

INVENTORY = [
    InventoryRow(
        dag="bietlejuice.enrich_agents_matias",
        task="load-enrich-eval-session-bundle",
        table="eval_session_bundle",
        files_location="s3://bucket/enrich/agents_matias/eval_session_bundle/",
    ),
    InventoryRow(
        dag="bietlejuice.enrich_agents_matias",
        task="load-enrich-matias-session-summary",
        table="matias_session_summary",
        files_location="s3://bucket/enrich/agents_matias/matias_session_summary/",
    ),
    InventoryRow(
        dag="bietlejuice.enrich_chatbot",
        task="load-enrich-sessions",
        table="sessions",
        files_location="s3://bucket/enrich/chatbot/sessions/",
    ),
    InventoryRow(
        dag="bietlejuice.langfuse",
        task="load-clean-traces",
        table="traces",
        files_location="s3://bucket/clean/langfuse/traces/",
    ),
]


def _write(tmp_path: Path, relative: str, content: str) -> Path:
    path = tmp_path / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def test_parse_dependency_entry_flags_first_run_suffix():
    assert parse_dependency_entry(
        "bietlejuice.enrich_chatbot:load-enrich-sessions:first-run-of-day"
    ) == ProducerEdge(
        "bietlejuice.enrich_chatbot",
        "load-enrich-sessions",
        first_run_of_day=True,
    )


def test_parse_dependency_entry_without_suffix_waits_on_the_run():
    assert parse_dependency_entry(
        "bietlejuice.enrich_chatbot:load-enrich-sessions"
    ) == ProducerEdge(
        "bietlejuice.enrich_chatbot",
        "load-enrich-sessions",
        first_run_of_day=False,
    )


def test_parse_dependency_entry_alias_suffix_is_not_first_run_of_day():
    edge = parse_dependency_entry(
        "bietlejuice.enrich_chatbot:load-enrich-sessions:alias"
    )
    assert edge == ProducerEdge(
        "bietlejuice.enrich_chatbot",
        "load-enrich-sessions",
        first_run_of_day=False,
    )


def test_parse_dependency_entry_skips_non_task_uris():
    assert (
        parse_dependency_entry("quintoml.chatbot.wall_e.inference:first-run-of-day")
        is None
    )


def test_scan_declaration_prefixes_dag_id_and_inner_deps(tmp_path):
    path = _write(
        tmp_path,
        "agents/enrich_agents_matias/enrich_agents_matias_declaration.yml",
        DECLARATION,
    )
    dag_id, inner, schedule, owner, layer = scan_declaration(path)
    assert dag_id == "bietlejuice.enrich_agents_matias"
    assert inner == {
        "matias_session_summary": ("eval_session_bundle",),
    }
    assert schedule == "0 4 * * *"
    assert owner == "Data Agents"
    assert layer == "enrich"


def test_build_job_graph_reads_inner_and_yaml(tmp_path):
    _write(
        tmp_path,
        "agents/enrich_agents_matias/enrich_agents_matias_declaration.yml",
        DECLARATION,
    )
    _write(
        tmp_path,
        "conversational_xp/enrich_chatbot/enrich_chatbot_declaration.yml",
        PRODUCER_DECLARATION,
    )
    _write(tmp_path, "dependencies.yaml", DEPENDENCIES)
    graph = build_job_graph(tmp_path)
    assert graph.inner_upstream["bietlejuice.enrich_agents_matias"][
        "matias_session_summary"
    ] == ("eval_session_bundle",)
    assert graph.dag_upstreams["bietlejuice.enrich_agents_matias"] == (
        ProducerEdge(
            "bietlejuice.enrich_chatbot",
            "load-enrich-sessions",
            first_run_of_day=True,
        ),
    )
    assert graph.cron_dags == frozenset({"bietlejuice.enrich_agents_matias"})
    assert graph.owners == {
        "bietlejuice.enrich_agents_matias": "Data Agents",
    }
    assert graph.layers == {
        "bietlejuice.enrich_agents_matias": "enrich",
        "bietlejuice.enrich_chatbot": "enrich",
    }


def test_duplicate_yaml_edges_keep_the_run_specific_wait(tmp_path):
    _write(tmp_path, "dependencies.yaml", MIXED_DEPENDENCIES)
    graph = build_job_graph(tmp_path)
    assert graph.dag_upstreams["bietlejuice.enrich_chatbot"] == (
        ProducerEdge(
            "bietlejuice.langfuse",
            "load-clean-traces",
            first_run_of_day=False,
        ),
    )


def test_upstream_job_hops_from_bundle_uses_yaml_not_sql_lineage():
    graph = JobGraph(
        inner_upstream={
            "bietlejuice.enrich_agents_matias": {
                "matias_session_summary": ("eval_session_bundle",),
            }
        },
        dag_upstreams={
            "bietlejuice.enrich_agents_matias": (
                ProducerEdge(
                    "bietlejuice.enrich_chatbot",
                    "load-enrich-sessions",
                    first_run_of_day=True,
                ),
            ),
            "bietlejuice.enrich_chatbot": (
                ProducerEdge(
                    "bietlejuice.langfuse",
                    "load-clean-traces",
                    first_run_of_day=True,
                ),
            ),
        },
    )
    hops = upstream_job_hops(
        ["datalake_agents_matias.eval_session_bundle"],
        INVENTORY,
        graph,
    )
    assert hops == {
        ("bietlejuice.enrich_chatbot", "load-enrich-sessions"): Hop(
            1, first_run_of_day=True
        ),
        ("bietlejuice.langfuse", "load-clean-traces"): Hop(2, first_run_of_day=True),
    }


def test_upstream_job_hops_keeps_every_run_of_a_run_specific_edge():
    graph = JobGraph(
        dag_upstreams={
            "bietlejuice.enrich_agents_matias": (
                ProducerEdge(
                    "bietlejuice.enrich_chatbot",
                    "load-enrich-sessions",
                    first_run_of_day=False,
                ),
            ),
        },
    )
    hops = upstream_job_hops(["eval_session_bundle"], INVENTORY, graph)
    assert hops == {
        ("bietlejuice.enrich_chatbot", "load-enrich-sessions"): Hop(
            1, first_run_of_day=False
        ),
    }


def test_inner_dependency_hop_is_not_first_run_of_day():
    graph = JobGraph(
        inner_upstream={
            "bietlejuice.enrich_agents_matias": {
                "matias_session_summary": ("eval_session_bundle",),
            }
        },
    )
    hops = upstream_job_hops(["matias_session_summary"], INVENTORY, graph)
    assert hops == {
        (
            "bietlejuice.enrich_agents_matias",
            "load-enrich-eval-session-bundle",
        ): Hop(1, first_run_of_day=False),
    }


def test_job_reached_both_ways_keeps_every_run():
    graph = JobGraph(
        inner_upstream={
            "bietlejuice.enrich_agents_matias": {
                "matias_session_summary": ("eval_session_bundle",),
            }
        },
        dag_upstreams={
            "bietlejuice.enrich_agents_matias": (
                ProducerEdge(
                    "bietlejuice.enrich_agents_matias",
                    "load-enrich-eval-session-bundle",
                    first_run_of_day=True,
                ),
            ),
        },
    )
    hops = upstream_job_hops(["matias_session_summary"], INVENTORY, graph)
    assert hops[
        ("bietlejuice.enrich_agents_matias", "load-enrich-eval-session-bundle")
    ] == Hop(1, first_run_of_day=False)


def test_upstream_job_hops_skips_yaml_edges_of_cron_dag():
    graph = JobGraph(
        inner_upstream={
            "bietlejuice.enrich_agents_matias": {
                "matias_session_summary": ("eval_session_bundle",),
            }
        },
        dag_upstreams={
            "bietlejuice.enrich_agents_matias": (
                ProducerEdge("bietlejuice.enrich_chatbot", "load-enrich-sessions"),
            ),
            "bietlejuice.enrich_chatbot": (
                ProducerEdge("bietlejuice.langfuse", "load-clean-traces"),
            ),
        },
        cron_dags=frozenset({"bietlejuice.enrich_agents_matias"}),
    )
    hops = upstream_job_hops(
        ["datalake_agents_matias.eval_session_bundle"],
        INVENTORY,
        graph,
    )
    assert hops == {}


def test_upstream_job_hops_keeps_inner_deps_of_cron_dag():
    graph = JobGraph(
        inner_upstream={
            "bietlejuice.enrich_agents_matias": {
                "matias_session_summary": ("eval_session_bundle",),
            }
        },
        dag_upstreams={
            "bietlejuice.enrich_agents_matias": (
                ProducerEdge("bietlejuice.enrich_chatbot", "load-enrich-sessions"),
            ),
        },
        cron_dags=frozenset({"bietlejuice.enrich_agents_matias"}),
    )
    hops = upstream_job_hops(["matias_session_summary"], INVENTORY, graph)
    assert hops == {
        (
            "bietlejuice.enrich_agents_matias",
            "load-enrich-eval-session-bundle",
        ): Hop(1),
    }


def test_upstream_job_hops_from_summary_includes_inner_dep():
    graph = JobGraph(
        inner_upstream={
            "bietlejuice.enrich_agents_matias": {
                "matias_session_summary": ("eval_session_bundle",),
            }
        },
        dag_upstreams={
            "bietlejuice.enrich_agents_matias": (
                ProducerEdge(
                    "bietlejuice.enrich_chatbot",
                    "load-enrich-sessions",
                    first_run_of_day=True,
                ),
            ),
        },
    )
    hops = upstream_job_hops(
        ["matias_session_summary"],
        INVENTORY,
        graph,
    )
    assert hops[
        ("bietlejuice.enrich_agents_matias", "load-enrich-eval-session-bundle")
    ] == Hop(1, first_run_of_day=False)
    assert hops[("bietlejuice.enrich_chatbot", "load-enrich-sessions")] == Hop(
        1, first_run_of_day=True
    )


def test_upstream_job_hops_respects_max_hop_level():
    graph = JobGraph(
        inner_upstream={},
        dag_upstreams={
            "bietlejuice.enrich_agents_matias": (
                ProducerEdge(
                    "bietlejuice.enrich_chatbot",
                    "load-enrich-sessions",
                    first_run_of_day=True,
                ),
            ),
            "bietlejuice.enrich_chatbot": (
                ProducerEdge(
                    "bietlejuice.langfuse",
                    "load-clean-traces",
                    first_run_of_day=True,
                ),
            ),
        },
    )
    hops = upstream_job_hops(
        ["eval_session_bundle"],
        INVENTORY,
        graph,
        max_hop_level=1,
    )
    assert hops == {
        ("bietlejuice.enrich_chatbot", "load-enrich-sessions"): Hop(
            1, first_run_of_day=True
        ),
    }


def test_upstream_job_hops_without_edges_is_empty():
    hops = upstream_job_hops(
        ["eval_session_bundle"],
        INVENTORY,
        JobGraph(),
    )
    assert hops == {}


def test_build_job_graph_stores_clean_layer(tmp_path):
    _write(
        tmp_path,
        "observability/langfuse/langfuse_declaration.yml",
        CLEAN_DECLARATION,
    )
    graph = build_job_graph(tmp_path)
    assert graph.layers == {"bietlejuice.langfuse": "clean"}


def test_frame_without_excluded_layers_drops_clean_keeps_hop_0():
    frame = pd.DataFrame(
        {
            "id_dag": [
                "bietlejuice.enrich_agents_matias",
                "bietlejuice.enrich_chatbot",
                "bietlejuice.langfuse",
            ],
            "level": [0, 1, 2],
            "id_task": ["seed", "sessions", "traces"],
        }
    )
    layers = {
        "bietlejuice.enrich_agents_matias": "clean",
        "bietlejuice.enrich_chatbot": "enrich",
        "bietlejuice.langfuse": "clean",
    }
    filtered = frame_without_excluded_layers(frame, layers, {"clean"})
    assert list(filtered["id_dag"]) == [
        "bietlejuice.enrich_agents_matias",
        "bietlejuice.enrich_chatbot",
    ]


def test_frame_without_excluded_layers_keeps_unknown_dags():
    frame = pd.DataFrame(
        {
            "id_dag": ["external.producer", "bietlejuice.langfuse"],
            "level": [1, 1],
        }
    )
    filtered = frame_without_excluded_layers(
        frame,
        {"bietlejuice.langfuse": "clean"},
        {"clean", "raw"},
    )
    assert list(filtered["id_dag"]) == ["external.producer"]


def test_lookup_inventory_rows_keeps_every_producer_of_a_table():
    inventory = INVENTORY + [
        InventoryRow(
            dag="bietlejuice.other",
            task="load-other-bundle",
            table="eval_session_bundle",
        )
    ]
    rows = lookup_inventory_rows("table_name", "eval_session_bundle", inventory)
    assert {(row.dag, row.task) for row in rows} == {
        ("bietlejuice.enrich_agents_matias", "load-enrich-eval-session-bundle"),
        ("bietlejuice.other", "load-other-bundle"),
    }


def test_lookup_inventory_rows_by_task_does_not_pick_other_producers():
    inventory = INVENTORY + [
        InventoryRow(
            dag="bietlejuice.other",
            task="load-other-sessions",
            table="sessions",
        )
    ]
    rows = lookup_inventory_rows("task_id", "load-enrich-sessions", inventory)
    assert [(row.dag, row.task, row.table) for row in rows] == [
        (
            "bietlejuice.enrich_chatbot",
            "load-enrich-sessions",
            "sessions",
        )
    ]


def test_lookup_inventory_rows_empty_value_is_empty():
    assert lookup_inventory_rows("table_name", "  ", INVENTORY) == []
