"""Tests for milestone strategy path → DAG mapping in deps generator."""

from __future__ import annotations

from bietlejuice.base.dependencies.file_dependency_generator import (
    FileDependencyGenerator,
)


def test_dag_name_from_milestone_strategy_path(tmp_path, monkeypatch):
    gen = FileDependencyGenerator()
    # Simulate path under dags/ after stripping DAG_PACKAGES_ROOT + domain.
    relative = (
        "dw_agent_performance/queries/dw/dim_agent_milestone/"
        "milestones/visit_events.sql.tpl"
    )
    monkeypatch.setattr(
        gen,
        "_get_path_without_base_or_owner",
        lambda path: relative,
    )
    assert (
        gen._dag_name_from_query_path("/fake/dags/agents/" + relative)
        == "bietlejuice.dw_agent_performance"
    )
